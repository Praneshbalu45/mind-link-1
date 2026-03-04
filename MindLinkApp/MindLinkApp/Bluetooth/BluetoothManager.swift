import Foundation
import ExternalAccessory
import CoreBluetooth
import Combine

// MARK: - Discovered Device

struct DiscoveredDevice: Identifiable, Hashable {
    enum Source { case externalAccessory, coreBluetooth }
    let id: UUID
    let name: String
    let rssi: Int
    let source: Source
    var eaAccessory: EAAccessory?
    var cbPeripheral: CBPeripheral?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    var signalBars: String {
        guard source == .coreBluetooth else { return "Paired ✓" }
        if rssi >= -50 { return "●●●●" } else if rssi >= -65 { return "●●●○" }
        else if rssi >= -80 { return "●●○○" } else { return "●○○○" }
    }
    var sourceLabel: String { source == .externalAccessory ? "Classic BT (paired)" : "BLE" }
}

private let kNeuroSkyProtocols = ["com.neurosky.thinkgear","com.neurosky.thinkgear.rawdata"]

// MARK: - Bluetooth Manager

class BluetoothManager: NSObject, ObservableObject {

    // MARK: Published
    @Published var scanState: ScanState = .idle
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var latestReading: EEGReading? = nil
    @Published var alertMessage: String? = nil
    @Published var phase: MonitoringPhase = .calibrating
    @Published var alertHistory: [EEGAlert] = []
    @Published var calibrationProgress: Double = 0
    @Published var rawPacketsReceived: Int = 0
    @Published var rawBytesReceived: Int = 0
    @Published var lastRawValue: Int = 0
    @Published var rawHexPreview: String = ""
    @Published var signalQuality: TGAM1Packet.SignalQuality = .noContact
    @Published var rawEEGSamples: [Double] = []   // ring buffer published at 20fps
    @Published var packetRateHz: Double = 0        // packets per second
    @Published var latestPacket: TGAM1Packet? = nil // full raw packet for Device Test tab

    enum ScanState: Equatable {
        case idle, scanning, connecting(String), connected(String), error(String)
    }

    // MARK: Pipeline
    private let signalProcessor  = SignalProcessor()
    private let featureExtractor = FeatureExtractor()
    private let predictor        = FatiguePredictor()
    private let alertSystem      = AlertSystem()

    // MARK: Raw EEG ring buffer (feeds ECG chart at 20fps)
    private var rawRingBuffer: [Double] = []
    private let ringSize = 512
    private var displayTimer: Timer?
    private var packetCountWindow: Int = 0
    private var rateTimer: Timer?

    // MARK: Parser
    private let parser = TGAM1Parser()

    // MARK: BT
    private var eaSession: EASession?
    private var centralManager: CBCentralManager!
    private var cbPeripheral: CBPeripheral?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)

        // Wire parser → pipeline
        parser.onPacket = { [weak self] packet in
            self?.processPipelinePacket(packet)
        }
        // Wire raw samples → ECG ring buffer (called on BT thread)
        parser.onRawSample = { [weak self] value in
            guard let self else { return }
            self.rawRingBuffer.append(Double(value))
            if self.rawRingBuffer.count > self.ringSize { self.rawRingBuffer.removeFirst() }
        }
        // Wire raw bytes → hex preview
        parser.onRawBytes = { [weak self] bytes in
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            DispatchQueue.main.async { self?.rawHexPreview = hex }
        }
        // 20fps timer → publish ring buffer to UI
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snap = self.rawRingBuffer
            DispatchQueue.main.async { self.rawEEGSamples = snap }
        }
        // 1s rate counter
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let rate = Double(self.packetCountWindow)
            DispatchQueue.main.async { self.packetRateHz = rate }
            self.packetCountWindow = 0
        }

        // Wire alert system → UI
        alertSystem.onAlert = { [weak self] alert in
            DispatchQueue.main.async {
                self?.alertMessage = alert.message
                self?.alertHistory.insert(alert, at: 0)
                if (self?.alertHistory.count ?? 0) > 100 { self?.alertHistory.removeLast() }
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(accessoryConnected(_:)),
            name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryDisconnected(_:)),
            name: .EAAccessoryDidDisconnect, object: nil)
        EAAccessoryManager.shared().registerForLocalNotifications()
    }

    // MARK: - Full EEG Pipeline

    private func processPipelinePacket(_ packet: TGAM1Packet) {
        // 1. Signal processing — compute frequency bands
        let bands: BandPowers
        let totalPower = packet.powerDict.values.reduce(0, +)
        if totalPower > 0 {
            bands = signalProcessor.processTGAMPowerData(packet.powerDict)
        } else {
            bands = signalProcessor.processRawEEG(Double(packet.rawEEG))
        }

        let ratios = bands.ratios

        // 2. Feature extraction
        featureExtractor.addSample(
            attention: packet.attention > 0 ? packet.attention : nil,
            meditation: packet.meditation > 0 ? packet.meditation : nil,
            bands: bands, ratios: ratios
        )

        // 3. Determine phase
        let currentPhase: MonitoringPhase = featureExtractor.baselineEstablished ? .monitoring : .calibrating

        // 4. Run predictor once baseline established
        let prediction: PredictionResult
        if featureExtractor.baselineEstablished {
            let features = featureExtractor.extractFeatures()
            prediction = predictor.predict(features)
            alertSystem.checkAlerts(features: features, prediction: prediction)
        } else {
            prediction = PredictionResult()
        }

        // 5. Build EEGReading for UI
        let reading = EEGReading(
            timestamp:    Date(),
            attention:    packet.attention,
            meditation:   packet.meditation,
            delta:        bands.delta, theta: bands.theta,
            alpha:        bands.alpha, beta:  bands.beta, gamma: bands.gamma,
            fatigueScore: prediction.fatigueScore,
            fatigueLevel: prediction.fatigueLevel,
            cognitiveDrift: prediction.cognitiveDrift,
            phase:        currentPhase,
            rawValue:     packet.rawEEG
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestReading    = reading
            self.latestPacket     = packet
            self.phase            = currentPhase
            self.calibrationProgress = self.featureExtractor.calibrationProgress
            self.rawPacketsReceived  = self.featureExtractor.totalSamples
            self.lastRawValue  = packet.rawEEG
            self.signalQuality = packet.signalQuality
            self.packetCountWindow += 1
        }
    }

    // MARK: - Scan / Connect

    func startScan() {
        discoveredDevices.removeAll()
        scanState = .scanning
        refreshExternalAccessories()
        if centralManager.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func stopScan() {
        centralManager.stopScan()
        if case .scanning = scanState { scanState = .idle }
    }

    func connect(to device: DiscoveredDevice) {
        centralManager.stopScan()
        scanState = .connecting(device.name)
        resetPipeline()
        switch device.source {
        case .externalAccessory:
            if let acc = device.eaAccessory { openEASession(accessory: acc) }
        case .coreBluetooth:
            if let p = device.cbPeripheral { cbPeripheral = p; centralManager.connect(p) }
        }
    }

    func disconnect() {
        stopEASession()
        if let p = cbPeripheral { centralManager.cancelPeripheralConnection(p) }
        cbPeripheral = nil; scanState = .idle
        latestReading = nil; alertMessage = nil
        discoveredDevices.removeAll(); resetPipeline()
    }

    private func resetPipeline() {
        signalProcessor.reset(); featureExtractor.reset(); alertSystem.reset()
        parser.reset()
        phase = .calibrating; calibrationProgress = 0
        rawPacketsReceived = 0; rawBytesReceived = 0; lastRawValue = 0
        rawRingBuffer.removeAll(); rawEEGSamples = []
        packetRateHz = 0; packetCountWindow = 0
        latestPacket = nil; signalQuality = .noContact
        rawHexPreview = ""
    }

    // MARK: - ExternalAccessory

    private func refreshExternalAccessories() {
        for acc in EAAccessoryManager.shared().connectedAccessories {
            let dev = DiscoveredDevice(
                id: UUID(uuidString: String(format:"00000000-0000-%04X-0000-000000000000", acc.connectionID)) ?? UUID(),
                name: acc.name.isEmpty ? "MindLink / TGAM1" : acc.name,
                rssi: 0, source: .externalAccessory, eaAccessory: acc, cbPeripheral: nil
            )
            if !discoveredDevices.contains(where: { $0.id == dev.id }) {
                discoveredDevices.insert(dev, at: 0)
            }
        }
    }

    private func openEASession(accessory: EAAccessory) {
        let proto = accessory.protocolStrings.first { kNeuroSkyProtocols.contains($0) }
               ?? accessory.protocolStrings.first ?? kNeuroSkyProtocols[0]
        guard let session = EASession(accessory: accessory, forProtocol: proto) else {
            scanState = .error("Could not open EASession — re-pair MindLink"); return
        }
        eaSession = session
        session.inputStream?.delegate = self
        session.inputStream?.schedule(in: .main, forMode: .default)
        session.inputStream?.open()
        session.outputStream?.schedule(in: .main, forMode: .default)
        session.outputStream?.open()
        scanState = .connected(accessory.name.isEmpty ? "MindLink" : accessory.name)
    }

    private func stopEASession() {
        eaSession?.inputStream?.close(); eaSession?.inputStream?.remove(from: .main, forMode: .default)
        eaSession?.outputStream?.close(); eaSession?.outputStream?.remove(from: .main, forMode: .default)
        eaSession = nil
    }

    @objc private func accessoryConnected(_ n: Notification) {
        refreshExternalAccessories()
        if let acc = n.userInfo?[EAAccessoryKey] as? EAAccessory, case .scanning = scanState {
            let name = acc.name.lowercased()
            if ["mindlink","mindwave","tgam","neurosky","thinkgear","eeg","neuro"].contains(where: { name.contains($0) }) {
                let dev = DiscoveredDevice(id: UUID(), name: acc.name.isEmpty ? "MindLink" : acc.name,
                    rssi: 0, source: .externalAccessory, eaAccessory: acc, cbPeripheral: nil)
                connect(to: dev)
            }
        }
    }

    @objc private func accessoryDisconnected(_ n: Notification) {
        stopEASession(); scanState = .idle; latestReading = nil; resetPipeline()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startScan() }
    }

    private func eegScore(_ name: String) -> Int {
        let lower = name.lowercased()
        return ["mindlink","mindwave","tgam","neurosky","eeg","neuro","thinkgear","brainwave"]
            .contains(where: { lower.contains($0) }) ? 1 : 0
    }
}

// MARK: - StreamDelegate

extension BluetoothManager: StreamDelegate {
    func stream(_ aStream: Stream, handle event: Stream.Event) {
        guard event == .hasBytesAvailable, let s = aStream as? InputStream else { return }
        var buf = [UInt8](repeating: 0, count: 512)
        let n = s.read(&buf, maxLength: 512)
        if n > 0 {
            DispatchQueue.main.async { self.rawBytesReceived += n }
            parser.feed(Array(buf.prefix(n)))
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, case .scanning = scanState {
            central.scanForPeripherals(withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return }
        let dev = DiscoveredDevice(id: peripheral.identifier, name: name,
            rssi: RSSI.intValue, source: .coreBluetooth, eaAccessory: nil, cbPeripheral: peripheral)
        if !discoveredDevices.contains(where: { $0.id == dev.id }) {
            discoveredDevices.append(dev)
            discoveredDevices.sort { eegScore($0.name) > eegScore($1.name) }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self; peripheral.discoverServices(nil)
        scanState = .connected(peripheral.name ?? "EEG Device")
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        scanState = .error(error?.localizedDescription ?? "Connection failed")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cbPeripheral = nil; scanState = .idle; latestReading = nil; resetPipeline()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.startScan() }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices _: Error?) {
        p.services?.forEach { p.discoverCharacteristics(nil, for: $0) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        service.characteristics?.forEach { c in
            if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                p.setNotifyValue(true, for: c)
            }
        }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let data = c.value { parser.feed(Array(data)) }
    }
}
