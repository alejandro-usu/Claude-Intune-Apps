<#
.SYNOPSIS
    Intune Win32 uninstall script for Python 3.14.7.

.DESCRIPTION
    Runs as SYSTEM. Removes Python 3.14.7 with its own installer. Packages installed with pip
    into C:\Program Files\Python314 go with it. Apps that depend on it, such as PyCharm, are not
    uninstalled; Intune doesn't remove dependents.

    Logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Uninstall.log
          (this script) and Python-3.14.7-Setup-Uninstall.log (the Python installer)
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PythonInstaller = Join-Path $PSScriptRoot 'python-3.14.7-amd64.exe'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'Python-3.14.7-Uninstall.log') -Append | Out-Null

$exitCode = 0
try {
    Write-Output "Running: `"$PythonInstaller`" /quiet /uninstall"
    $process = Start-Process -FilePath $PythonInstaller -WindowStyle Hidden -Wait -PassThru -ArgumentList (
        "/quiet /uninstall /log `"$(Join-Path $LogDir 'Python-3.14.7-Setup-Uninstall.log')`"")
    Write-Output "Exit code: $($process.ExitCode)"
    if ($process.ExitCode -in 1641, 3010) {
        $exitCode = 3010
    } elseif ($process.ExitCode -ne 0) {
        throw "Python uninstall failed with exit code $($process.ExitCode)"
    }

    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
