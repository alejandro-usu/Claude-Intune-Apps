# <APP NAME> <VERSION> (Intune Win32 app)

One or two sentences on what this installs and anything it configures.

| Component | Source | SHA-256 |
|---|---|---|
| `example-<VERSION>-x64.msi` | https://vendor.example.com/downloads/example-<VERSION>-x64.msi | `<sha256>` |

Say where the hash was checked (the vendor's published checksum, a signed release page, etc.).

## Build

```sh
python3 tools/build.py <APP-FOLDER>
# -> out/<APP-FOLDER>/Install.intunewin
```

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | <APP NAME> <VERSION> |
| Publisher | <Vendor> |
| Install command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | |
| Disk space required | |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |

Logs: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<APP-FOLDER>-*.log`

## What the install does

1. ...

## Uninstall

...
