<#
.SYNOPSIS
    Intune Win32 install script for Python 3.14.7 (64-bit, all users).

.DESCRIPTION
    Runs as SYSTEM. Installs to C:\Program Files\Python314, adds Python to the system PATH and
    installs the py launcher for all users. Patch releases of 3.14 install to the same folder,
    so apps configured with this path (such as PyCharm) keep working after an upgrade.

    Logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Install.log
          (this script) and Python-3.14.7-Setup.log (the Python installer)
#>
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PythonInstaller = Join-Path $PSScriptRoot 'python-3.14.7-amd64.exe'
$PythonDir = Join-Path $env:ProgramFiles 'Python314'
$PythonExe = Join-Path $PythonDir 'python.exe'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'Python-3.14.7-Install.log') -Append | Out-Null

$exitCode = 0
try {
    $pythonArgs = @(
        '/quiet'
        'InstallAllUsers=1'
        "TargetDir=`"$PythonDir`""
        'PrependPath=1'
        'AssociateFiles=1'
        'Shortcuts=1'
        'Include_launcher=1'
        'InstallLauncherAllUsers=1'
        'Include_pip=1'
        'Include_test=0'
        "/log `"$(Join-Path $LogDir 'Python-3.14.7-Setup.log')`""
    ) -join ' '
    Write-Output "Running: `"$PythonInstaller`" $pythonArgs"
    $process = Start-Process -FilePath $PythonInstaller -ArgumentList $pythonArgs -Wait -PassThru -WindowStyle Hidden
    Write-Output "Exit code: $($process.ExitCode)"
    if ($process.ExitCode -in 1641, 3010) {
        $exitCode = 3010
    } elseif ($process.ExitCode -ne 0) {
        throw "Python install failed with exit code $($process.ExitCode)"
    }
    if (-not (Test-Path -LiteralPath $PythonExe)) { throw "Python install finished but '$PythonExe' is missing" }

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
