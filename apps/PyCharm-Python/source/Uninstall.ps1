<#
.SYNOPSIS
    Intune Win32 uninstall script for PyCharm 2026.2.3 + Python 3.14.7.

.DESCRIPTION
    Runs as SYSTEM. Removes PyCharm 2026.2.3, Python 3.14.7, the Active Setup entry and the
    per-user defaults script. Users' own PyCharm settings in %APPDATA% are left alone.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PyCharm-2026.2.3-Python-3.14.7-Uninstall.log
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PythonInstaller = Join-Path $PSScriptRoot 'python-3.14.7-amd64.exe'
$PyCharmDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm 2026.2.3'
$DefaultsDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm-Python-Defaults'
$ActiveSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\PyCharm2026.2-Python3.14-Interpreter'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'PyCharm-2026.2.3-Python-3.14.7-Uninstall.log') -Append | Out-Null

$exitCode = 0
try {
    # --- PyCharm ------------------------------------------------------------------------------
    Get-Process -Name pycharm64, pycharm -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "$PyCharmDir\*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $uninstaller = Join-Path $PyCharmDir 'bin\Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        Write-Output "Running: `"$uninstaller`" /S"
        Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait
        # The NSIS uninstaller copies itself to %TEMP% and continues from there, so the process
        # above returns early. Wait for the real work to finish.
        $deadline = (Get-Date).AddMinutes(15)
        while ((Test-Path -LiteralPath (Join-Path $PyCharmDir 'bin\pycharm64.exe')) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
        }
        Get-Process -Name 'Un_*', 'Au_*' -ErrorAction SilentlyContinue | Wait-Process -Timeout 300 -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $PyCharmDir) {
        Remove-Item -LiteralPath $PyCharmDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # --- Python -------------------------------------------------------------------------------
    Write-Output "Running: `"$PythonInstaller`" /quiet /uninstall"
    $process = Start-Process -FilePath $PythonInstaller -WindowStyle Hidden -Wait -PassThru -ArgumentList (
        "/quiet /uninstall /log `"$(Join-Path $LogDir 'Python-3.14.7-Uninstall.log')`"")
    Write-Output "Exit code: $($process.ExitCode)"
    if ($process.ExitCode -in 1641, 3010) {
        $exitCode = 3010
    } elseif ($process.ExitCode -ne 0) {
        throw "Python uninstall failed with exit code $($process.ExitCode)"
    }

    # --- Firewall rule and per-user defaults hook ---------------------------------------------
    Get-NetFirewallRule -Group 'PyCharm 2026.2.3' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Remove-Item -Path $ActiveSetupKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $DefaultsDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
