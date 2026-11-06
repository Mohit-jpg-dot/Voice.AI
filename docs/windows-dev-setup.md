# Windows Developer Environment & Build Setup

This guide details how to set up the development environment, compile, run, and test **Voice.AI for Windows** on Windows 10 (22H2+) or Windows 11.

---

## 1. Pinned Toolchain & Prerequisites

| Component | Pinned Version | Purpose |
|---|---|---|
| **OS** | Windows 10 Build 19045+ (22H2) or Windows 11 Build 22621+ | Base runtime platform |
| **SDK** | Windows 10 SDK `10.0.19041.0` or Windows 11 SDK `10.0.22621.0` | Win32, UIA, and Windows.Graphics |
| **.NET SDK** | .NET 8.0 SDK (8.0.200+) or .NET 9.0 SDK | Core C# compiler and runtime |
| **Windows App SDK**| `1.5.240311000` (WinUI 3) | Modern desktop UI framework |
| **Visual Studio** | Visual Studio 2022 (Community / Professional 17.8+) | IDE and C++ build tools |

### Required Visual Studio Workloads
Install Visual Studio 2022 with the following workloads:
1. **.NET Desktop Development** (includes .NET 8 runtime, C# compiler).
2. **Desktop Development with C++** (needed for whisper.cpp and native interop).
3. **Windows Application Development** (Windows App SDK C# templates).

---

## 2. Directory Layout

```
windows/
├── VoiceAI.Core/              # Cross-platform .NET 8 core library (shared logic)
│   ├── Brain/                 # Model router, Cloud providers, Ollama client, Google Free
│   ├── Grammar/               # Hindi/Hinglish/English grammar & intent classifier
│   ├── Math/                  # Offline deterministic MathEngine
│   ├── Memory/                # Encrypted history & user memory files
│   └── Tools/                 # Tool schema, approvals, and execution planner
├── VoiceAI.Windows/           # Native Windows 11/10 WinUI 3 application
│   ├── Views/                 # TopCenterIslandWindow, Settings, SetupWizard
│   ├── Services/              # WASAPI audio, UIA control, SMTC, DPAPI, OCR
│   ├── App.xaml               # Application entry point and tray setup
│   └── Package.appxmanifest   # MSIX identity and capabilities
└── tests/
    └── VoiceAI.Core.Tests/    # Cross-platform unit tests (runs on macOS & Windows)
```

---

## 3. Building from Command Line

### Step 1: Restore and Build Shared Core
```cmd
cd windows/VoiceAI.Core
dotnet restore
dotnet build -c Release
```

### Step 2: Run Cross-Platform Core Unit Tests
```cmd
cd ../tests/VoiceAI.Core.Tests
dotnet test --logger "console;verbosity=detailed"
```

### Step 3: Build the Windows Application
```cmd
cd ../VoiceAI.Windows
dotnet restore
dotnet publish -c Release -r win-x64 --self-contained false
```
The compiled executable is placed under:
`windows/VoiceAI.Windows/bin/x64/Release/net8.0-windows10.0.19041.0/win-x64/Voice.AI.exe`

---

## 4. Packaging as MSIX / MSI

### Building the MSIX Package
```cmd
dotnet publish windows/VoiceAI.Windows/VoiceAI.Windows.csproj -c Release -p:GenerateAppxPackageOnBuild=true
```

### Development Certificate for Local Testing
To test the MSIX on a Windows machine without an enterprise certificate:
```powershell
# Create a local development self-signed certificate
New-SelfSignedCertificate -Type Custom -Subject "CN=VoiceAI, O=VoiceAI, C=US" -KeyUsage DigitalSignature -FriendlyName "Voice.AI Dev Certificate" -CertStoreLocation "Cert:\CurrentUser\My"

# Export and trust in Trusted People store
Export-Certificate -Cert (Get-ChildItem Cert:\CurrentUser\My | Where-Object Subject -match "VoiceAI") -FilePath "VoiceAI-Dev.cer"
Import-Certificate -FilePath "VoiceAI-Dev.cer" -CertStoreLocation "Cert:\LocalMachine\TrustedPeople"
```

---

## 5. Troubleshooting & Common Issues

1. **Microphone Access Denied**:
   - Ensure microphone permission is enabled in Windows Settings: `ms-settings:privacy-microphone`.
2. **Elevated Windows Injection Blocked (UIPI)**:
   - Non-elevated Voice.AI cannot send synthetic input to elevated windows (e.g. Task Manager). Run Voice.AI as Administrator if automating elevated administrator windows is required.
3. **Mica Effect Fallback**:
   - On Windows 10, Mica material falls back automatically to solid dark acrylic (`#121214`).

