import Foundation
import Network

// MARK: - SMTP Email Sender (Hostinger)
// Sender credentials are embedded — only recipient is user-configurable.

actor SMTPSender {

    static let shared = SMTPSender()

    // ── Hardcoded sender (hidden from UI) ──────────────────────────
    private let smtpHost    = "smtp.hostinger.com"
    private let smtpPort: UInt16 = 465
    private let senderEmail = "info@setups.works"
    private let senderPass  = "Thilak_dr1"

    // MARK: - Error types

    enum SMTPError: Error, LocalizedError {
        case connectionFailed(String)
        case authFailed
        case serverRejectedRecipient
        case sendFailed(String)

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let m): return "Connection failed: \(m)"
            case .authFailed:              return "SMTP authentication failed"
            case .serverRejectedRecipient: return "Server rejected recipient address"
            case .sendFailed(let m):       return "Send failed: \(m)"
            }
        }
    }

    // MARK: - Public Send

    func send(to recipient: String, subject: String, body: String) async throws {
        let conn = try await connectSSL()

        try await expect(conn, prefix: "220")                   // greeting
        try await write(conn,  "EHLO mindlinkeeg.app\r\n")
        try await expect(conn, prefix: "250")                   // EHLO OK

        try await write(conn,  "AUTH LOGIN\r\n")
        try await expect(conn, prefix: "334")                   // ask username
        try await write(conn,  b64(senderEmail) + "\r\n")
        try await expect(conn, prefix: "334")                   // ask password
        try await write(conn,  b64(senderPass)  + "\r\n")
        let authResp = try await readLine(conn)
        guard authResp.hasPrefix("235") else { throw SMTPError.authFailed }

        try await write(conn, "MAIL FROM:<\(senderEmail)>\r\n")
        try await expect(conn, prefix: "250")

        try await write(conn, "RCPT TO:<\(recipient)>\r\n")
        let rcpt = try await readLine(conn)
        guard rcpt.hasPrefix("250") else { throw SMTPError.serverRejectedRecipient }

        try await write(conn, "DATA\r\n")
        try await expect(conn, prefix: "354")

        let date = DateFormatter.rfc2822.string(from: Date())
        let msg  = """
        Date: \(date)\r\n\
        From: MindLink EEG <\(senderEmail)>\r\n\
        To: \(recipient)\r\n\
        Subject: \(subject)\r\n\
        Content-Type: text/plain; charset=UTF-8\r\n\
        \r\n\
        \(body)\r\n\
        .\r\n
        """
        try await write(conn, msg)
        try await expect(conn, prefix: "250")                   // accepted

        try await write(conn, "QUIT\r\n")
        conn.cancel()
    }

    // MARK: - Connection (SSL/TLS port 465)

    private func connectSSL() async throws -> NWConnection {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(smtpHost),
            port: NWEndpoint.Port(rawValue: smtpPort)!
        )
        let conn = NWConnection(to: endpoint, using: .tls)
        return try await withCheckedThrowingContinuation { cont in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    cont.resume(returning: conn)
                case .failed(let e):
                    cont.resume(throwing: SMTPError.connectionFailed(e.localizedDescription))
                case .waiting(let e):
                    conn.cancel()
                    cont.resume(throwing: SMTPError.connectionFailed(e.localizedDescription))
                default: break
                }
            }
            conn.start(queue: .global())
        }
    }

    // MARK: - SMTP helpers

    private func readLine(_ conn: NWConnection) async throws -> String {
        var buf = ""
        while !buf.contains("\n") {
            let chunk = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, err in
                    if let err { cont.resume(throwing: err); return }
                    cont.resume(returning: data.flatMap { String(bytes: $0, encoding: .utf8) } ?? "")
                }
            }
            buf += chunk
        }
        return buf
    }

    private func expect(_ conn: NWConnection, prefix: String) async throws {
        let line = try await readLine(conn)
        guard line.hasPrefix(prefix) else {
            throw SMTPError.sendFailed("Expected \(prefix), got: \(line.prefix(80))")
        }
    }

    private func write(_ conn: NWConnection, _ text: String) async throws {
        guard let data = text.data(using: .utf8) else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    private func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
}

// MARK: - RFC2822 Date

private extension DateFormatter {
    static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()
}
