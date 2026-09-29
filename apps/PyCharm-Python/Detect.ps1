<#
.SYNOPSIS
    Intune custom detection script for PyCharm 2026.2.3 + Python 3.14.7.

.DESCRIPTION
    Reports "installed" (writes to stdout, exits 0) only when all of these are present:
      - PyCharm 2026.2.3 in C:\Program Files\JetBrains\PyCharm 2026.2.3
      - Python 3.14.7 (64-bit, all users) registered under HKLM\SOFTWARE\Python\PythonCore\3.14
      - the Active Setup entry for the per-user defaults, at this package's version
      - the PyCharm 2026.2.3 firewall rule
#>
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')

try {
    $productInfo = Join-Path $programFiles 'JetBrains\PyCharm 2026.2.3\product-info.json'
    if (-not (Test-Path -LiteralPath $productInfo)) { exit 1 }
    if ((Get-Content -LiteralPath $productInfo -Raw | ConvertFrom-Json).version -ne '2026.2.3') { exit 1 }

    $pythonKey = $hklm.OpenSubKey('SOFTWARE\Python\PythonCore\3.14')
    if (-not $pythonKey) { exit 1 }
    if ($pythonKey.GetValue('Version') -ne '3.14.7') { exit 1 }
    $installPath = $hklm.OpenSubKey('SOFTWARE\Python\PythonCore\3.14\InstallPath')
    if (-not $installPath) { exit 1 }
    $pythonExe = $installPath.GetValue('ExecutablePath')
    if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) { exit 1 }

    $activeSetup = $hklm.OpenSubKey('SOFTWARE\Microsoft\Active Setup\Installed Components\PyCharm2026.2-Python3.14-Interpreter')
    if (-not $activeSetup -or -not $activeSetup.GetValue('StubPath')) { exit 1 }
    # Must match $ActiveSetupVersion in Install.ps1, so devices with an older package reinstall.
    if ($activeSetup.GetValue('Version') -ne '2026,2,3,2') { exit 1 }

    if (-not (Get-NetFirewallRule -Group 'PyCharm 2026.2.3' -ErrorAction SilentlyContinue)) { exit 1 }

    Write-Output "PyCharm 2026.2.3 and Python 3.14.7 detected ($pythonExe)"
    exit 0
} catch {
    exit 1
}
