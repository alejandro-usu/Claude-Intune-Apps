# Python 3.14.7 (Intune Win32 app)

Installs 64-bit Python 3.14.7 for all users in `C:\Program Files\Python314`, adds it to the
system PATH, and installs the `py` launcher. Other apps can depend on it, such as
[PyCharm](../PyCharm/).

| Component | Source | SHA-256 |
|---|---|---|
| `python-3.14.7-amd64.exe` | https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe | `9d9eb2709ef81bf5cd30db3c2096bdbc4ea10087c22e62f27d356b36f6ae9649` |

The hash matches the `sha256_sum` python.org publishes for this file.

## Build the package

```sh
python3 tools/build.py Python-3.14
# -> out/Python-3.14/Install.intunewin
```

GitHub Actions also builds it whenever a push changes this folder, and publishes it as the
**Python-3.14-3.14.7** artifact. See the [repo README](../../README.md).

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | Python 3.14.7 |
| Publisher | Python Software Foundation |
| Install command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | Windows 10 21H2 or later |
| Disk space required | 500 MB |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |

Logs, in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`:
- `Python-3.14.7-Install.log` and `Python-3.14.7-Uninstall.log` from the scripts
- `Python-3.14.7-Setup.log` and `Python-3.14.7-Setup-Uninstall.log` from the Python installer

## What the install does

[`source/Install.ps1`](source/Install.ps1), running as SYSTEM, runs:

```
python-3.14.7-amd64.exe /quiet InstallAllUsers=1 TargetDir="C:\Program Files\Python314"
  PrependPath=1 AssociateFiles=1 Shortcuts=1 Include_launcher=1 InstallLauncherAllUsers=1
  Include_pip=1 Include_test=0
```

A reboot request from the installer (exit code 3010 or 1641) is passed on to Intune as 3010,
a soft reboot.

## Updating to a new 3.14 patch release

Patch releases install over this one in the same folder, so apps that point at
`C:\Program Files\Python314\python.exe` keep working. To update:
1. Change the URL, hash and version in `app.json`.
2. Change `3.14.7` in the scripts and `Detect.ps1`.
3. Add it to Intune as a new app that supersedes this one, with **Uninstall previous version**
   set to **No**.

## Uninstall

[`source/Uninstall.ps1`](source/Uninstall.ps1) runs `python-3.14.7-amd64.exe /quiet /uninstall`.
Packages installed with pip into `C:\Program Files\Python314` go with it. Apps that depend on
Python stay installed.
