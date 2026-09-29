<#
.SYNOPSIS
    Intune custom detection script for Python 3.14.7.

.DESCRIPTION
    Reports "installed" (writes to stdout, exits 0) when Python 3.14.7 (64-bit, all users) is
    registered under HKLM\SOFTWARE\Python\PythonCore\3.14 and its python.exe exists.
#>
$hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')

try {
    $pythonKey = $hklm.OpenSubKey('SOFTWARE\Python\PythonCore\3.14')
    if (-not $pythonKey) { exit 1 }
    if ($pythonKey.GetValue('Version') -ne '3.14.7') { exit 1 }
    $installPath = $hklm.OpenSubKey('SOFTWARE\Python\PythonCore\3.14\InstallPath')
    if (-not $installPath) { exit 1 }
    $pythonExe = $installPath.GetValue('ExecutablePath')
    if (-not $pythonExe -or -not (Test-Path -LiteralPath $pythonExe)) { exit 1 }

    Write-Output "Python 3.14.7 detected ($pythonExe)"
    exit 0
} catch {
    exit 1
}
