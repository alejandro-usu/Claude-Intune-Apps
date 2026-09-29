# PyCharm 2026.2.3 + Python 3.14.7 (Intune Win32 app)

Installs Python 3.14.7 and PyCharm 2026.2.3 for all users, and makes Python 3.14.7 the
default interpreter in PyCharm for every user on the device.

| Component | Source | SHA-256 |
|---|---|---|
| `python-3.14.7-amd64.exe` | https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe | `9d9eb2709ef81bf5cd30db3c2096bdbc4ea10087c22e62f27d356b36f6ae9649` |
| `pycharm-2026.2.3.exe` (build 262.10968.92) | https://download.jetbrains.com/python/pycharm-2026.2.3.exe | `f47b0e48ce06a903b94245bbe8a312f2196205a12264ee47b0cf1595a1443362` |

Both hashes match what python.org and JetBrains publish.

## Build the package

### With GitHub Actions

[`.github/workflows/build-pycharm-python.yml`](../.github/workflows/build-pycharm-python.yml) builds
the package whenever a push changes it. To run it by hand, open **Actions → Build PyCharm 2026.2.3 +
Python 3.14.7 package → Run workflow**. The button only appears once the workflow is on the default
branch. When the run finishes, download the **Install.intunewin** artifact from the run page. GitHub
wraps it in a .zip, so extract it before uploading to Intune. The run summary shows the package's
SHA-256. Artifacts are kept for 14 days.

### Locally

The installers (about 1 GB) and the `.intunewin` are too large for git, so `build.py`
downloads them, checks their hashes, and builds the package:

```sh
pip install cryptography
python3 PyCharm-2026.2.3-Python-3.14.7/build.py
# -> PyCharm-2026.2.3-Python-3.14.7/output/Install.intunewin
```

`build.py` uses [`tools/intunewin.py`](../tools/intunewin.py), which writes the same format
as Microsoft's Win32 Content Prep Tool and runs on any OS. To use Microsoft's tool on Windows
instead, put the two installers in `source\` and run:

```bat
IntuneWinAppUtil.exe -c source -s Install.ps1 -o output
```

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | PyCharm 2026.2.3 with Python 3.14.7 |
| Publisher | JetBrains / Python Software Foundation |
| Install command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults (0 success, 1707 success, 3010 soft reboot, 1641 hard reboot, 1618 retry) |
| OS architecture | x64 |
| Minimum OS | Windows 10 21H2 or later (PyCharm 2026.2 requires 64-bit Windows 10+) |
| Disk space required | 5,000 MB |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |

Installs, uninstalls and per-user changes are logged to
`C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\` (`PyCharm-2026.2.3-Python-3.14.7-*.log`,
`Python-3.14.7-*.log`, `PyCharm-2026.2.3-Install.log`), so "Collect diagnostics" picks them up.

## What the install does

[`source/Install.ps1`](source/Install.ps1), running as SYSTEM:

1. **Python 3.14.7**: `python-3.14.7-amd64.exe /quiet InstallAllUsers=1 TargetDir="C:\Program Files\Python314" PrependPath=1 Include_launcher=1 InstallLauncherAllUsers=1 ...`.
   Python goes on the system PATH and the `py` launcher is installed for everyone.
2. **PyCharm 2026.2.3**: `pycharm-2026.2.3.exe /S /CONFIG=silent.config /D=C:\Program Files\JetBrains\PyCharm 2026.2.3`.
   [`silent.config`](source/silent.config) sets `mode=admin` (all users) and turns off the desktop
   shortcut, PATH change, context menu entry and `.py` association.
3. **Default interpreter, future logons**: copies
   [`Set-PyCharmInterpreter.ps1`](source/Set-PyCharmInterpreter.ps1) to
   `C:\Program Files\JetBrains\PyCharm-Python-Defaults\` (only admins can write there) and
   registers it with **Active Setup**, so Windows runs it once for each user at their next logon.
4. **Default interpreter, now**: runs the same script as SYSTEM against every existing profile
   under `C:\Users`, so users who are already signed in don't need to log off.

If the script is invoked on a 32-bit PowerShell (which the Intune Management Extension can
do), it relaunches itself as 64-bit so `Program Files` and `HKLM` aren't redirected.

## How the default interpreter is set

PyCharm has no machine-wide interpreter setting. Interpreters live in each user's config
folder, `%APPDATA%\JetBrains\PyCharm2026.2\options\`. `Set-PyCharmInterpreter.ps1` writes
three files there:

| File | What the script sets |
|---|---|
| `jdk.table.xml` | Adds a `Python SDK` entry named **Python 3.14** for `C:\Program Files\Python314\python.exe` (flavor `WinPythonSdkFlavor`). If an entry for that `python.exe` already exists, it reuses that entry. If another interpreter already uses the name, it picks `Python 3.14 (2)`. |
| `project.default.xml` | Points the default project's `ProjectRootManager` at that SDK, so new projects and projects opened without an interpreter get Python 3.14.7. |
| `pySdk.xml` | Sets `PySdkSettings.PREFERRED_VIRTUALENV_BASE_SDK` to that `python.exe`, so the New Project wizard picks Python 3.14.7 as the base interpreter when it creates a new venv. |

It edits these files in place and keeps the rest of their contents. Running it again changes
nothing.

**Keeping settings from older PyCharm versions.** The first time a user starts PyCharm 2026.2,
it offers to import settings from their previous version (for example `PyCharm2026.1`). Two
details of that import, confirmed in the 2026.2.3 build (`ConfigImportHelper`, `InitialConfigImportState`):

- PyCharm only treats the config folder as already set up, and skips the import, when
  `options\other.xml`, `options\ide.general.xml` or `options\options.xml` exists. The script
  never writes those files, so the import still happens.
- During the import, PyCharm skips any file that already exists in the new folder. On its own,
  that would mean the user's older interpreter list and new-project defaults were not brought
  across. So when the 2026.2 folder hasn't been set up yet, the script starts from the newest
  older `PyCharm*`/`PyCharmCE*` copy of each file and then adds Python 3.14.7. The user keeps
  their old interpreters and also gets the new default.

**Caveats**

- If PyCharm is running while the SYSTEM pass edits a user's files, PyCharm overwrites them
  when it exits. Active Setup runs at logon, before PyCharm can start, so it covers anyone
  this affects at their next logon. To make Active Setup run again for everyone, bump
  `$ActiveSetupVersion` in `Install.ps1`.
- With folder redirection of `AppData\Roaming`, the SYSTEM pass writes to the local profile
  path. Active Setup still writes to the user's real `%APPDATA%` at their next logon.
- Existing projects keep whatever interpreter they already use. The default only applies to
  new projects.

## Uninstall

[`source/Uninstall.ps1`](source/Uninstall.ps1) stops PyCharm, runs `bin\Uninstall.exe /S` and
waits for it to finish, runs `python-3.14.7-amd64.exe /quiet /uninstall`, then removes the
Active Setup entry and the defaults script. It leaves users' own PyCharm settings in `%APPDATA%`
alone.
