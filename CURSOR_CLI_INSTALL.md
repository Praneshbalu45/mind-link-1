# Cursor CLI Installation Guide

## Quick Installation (Windows)

### Method 1: Using PowerShell (Recommended)

Open **PowerShell as Administrator** and run:

```powershell
# Download and install Cursor CLI
curl https://cursor.com/install -fsS | bash
```

Or if curl is not available, use PowerShell's Invoke-WebRequest:

```powershell
# Download installer
Invoke-WebRequest -Uri "https://cursor.com/install" -OutFile "$env:TEMP\cursor-install.sh"
# Note: This downloads a bash script, so you may need WSL or Git Bash
```

### Method 2: Using Git Bash (If you have Git installed)

1. Open **Git Bash**
2. Run:
```bash
curl https://cursor.com/install -fsS | bash
```

### Method 3: Manual Installation

1. **Download Cursor IDE** (includes CLI):
   - Visit: https://cursor.com/download
   - Download Windows installer
   - Run `Cursor-Setup.exe`
   - The CLI should be available after installation

2. **Add to PATH** (if needed):
   - Cursor CLI is usually installed at: `C:\Users\<YourUsername>\AppData\Local\Programs\cursor\resources\app\cli`
   - Add this to your system PATH

### Method 4: Using winget (Windows Package Manager)

```cmd
winget install Anysphere.Cursor
```

---

## Verify Installation

After installation, verify it works:

```cmd
cursor --version
```

Or:

```cmd
agent --version
```

---

## Using Cursor CLI

Once installed, you can use Cursor Agent from command line:

```bash
# Chat with agent
agent chat "help me with my code"

# Example: Find and fix bugs
agent chat "find one bug and fix it"

# Work on specific files
agent chat "review this file and suggest improvements"
```

---

## Troubleshooting

### If CLI not found after installation:

1. **Check PATH**:
   ```cmd
   echo %PATH%
   ```

2. **Restart terminal** after installation

3. **Manual PATH addition**:
   - Go to: System Properties → Environment Variables
   - Add Cursor installation directory to PATH

### If installation fails:

1. **Check internet connection**
2. **Run as Administrator**
3. **Try manual download** from cursor.com

---

## Alternative: Use Cursor IDE Directly

If CLI installation is problematic, you can:
- Use Cursor IDE GUI directly
- Access terminal within Cursor IDE
- Use Cursor's built-in features

---

## Notes

- Cursor CLI is currently in **beta**
- Requires Cursor subscription for full features
- Works best in trusted environments

---

**For your Phase 2 project**, you don't need Cursor CLI - you can use the IDE directly or regular Python commands!
