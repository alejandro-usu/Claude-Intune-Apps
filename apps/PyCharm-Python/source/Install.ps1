<#
.SYNOPSIS
    Intune Win32 install script: Python 3.14.7 + PyCharm 2026.2.3, with Python 3.14.7 set
    as PyCharm's default interpreter and PyCharm's first-run prompts pre-answered.

.DESCRIPTION
    Runs as SYSTEM. Steps:
      1. Install Python 3.14.7 for all users (C:\Program Files\Python314, on PATH, py launcher).
      2. Install PyCharm 2026.2.3 for all users (C:\Program Files\JetBrains\PyCharm 2026.2.3).
      3. Add a Windows Firewall rule for pycharm64.exe, so Windows doesn't ask each user
         whether to let PyCharm through the firewall.
      4. Copy Set-PyCharmUserDefaults.ps1 to an admin-only folder and register it with
         Active Setup, so it runs once for every user at their next logon. It accepts the
         JetBrains User Agreement, declines anonymous usage statistics and sets the default
         interpreter.
      5. Run Set-PyCharmUserDefaults.ps1 now for every existing user profile, so users who are
         already signed in get the settings without logging off.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PyCharm-2026.2.3-Python-3.14.7-Install.log
#>
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PythonVersion = '3.14.7'
$PythonInstaller = Join-Path $PSScriptRoot 'python-3.14.7-amd64.exe'
$PythonDir = Join-Path $env:ProgramFiles 'Python314'
$PythonExe = Join-Path $PythonDir 'python.exe'

$PyCharmInstaller = Join-Path $PSScriptRoot 'pycharm-2026.2.3.exe'
$PyCharmDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm 2026.2.3'

$DefaultsDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm-Python-Defaults'
$DefaultsScript = Join-Path $DefaultsDir 'Set-PyCharmUserDefaults.ps1'
$ActiveSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\PyCharm2026.2-Python3.14-Interpreter'
# Bump the last field to make Active Setup run again for users who already ran this version.
$ActiveSetupVersion = '2026,2,3,2'

# Inbound firewall rule for pycharm64.exe. Any rule for the program stops the Windows prompt.
# Block keeps PyCharm unreachable from other machines; its own features (debugger, built-in web
# server) talk over localhost, which Windows Firewall doesn't filter. Use 'Allow' instead if
# users need to reach PyCharm from another computer.
$FirewallAction = 'Block'
$FirewallGroup = 'PyCharm 2026.2.3'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'PyCharm-2026.2.3-Python-3.14.7-Install.log') -Append | Out-Null

function Invoke-Installer([string]$FilePath, [string]$Arguments, [int[]]$SuccessCodes = @(0)) {
    # Write-Host, not Write-Output: this function's output is its exit code. The transcript still logs it.
    Write-Host "Running: `"$FilePath`" $Arguments"
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    Write-Host "Exit code: $($process.ExitCode)"
    if ($SuccessCodes -notcontains $process.ExitCode) {
        throw "'$FilePath' failed with exit code $($process.ExitCode)"
    }
    return $process.ExitCode
}

$exitCode = 0
try {
    # --- 1. Python ----------------------------------------------------------------------------
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
        "/log `"$(Join-Path $LogDir 'Python-3.14.7-Install.log')`""
    ) -join ' '
    $pythonExit = Invoke-Installer $PythonInstaller $pythonArgs @(0, 1641, 3010)
    if ($pythonExit -in 1641, 3010) { $exitCode = 3010 }
    if (-not (Test-Path -LiteralPath $PythonExe)) { throw "Python install finished but '$PythonExe' is missing" }

    # --- 2. PyCharm ---------------------------------------------------------------------------
    # NSIS rule: /D= must come last and must not be quoted, even when the path has spaces.
    $pycharmArgs = "/S /CONFIG=`"$(Join-Path $PSScriptRoot 'silent.config')`" " +
        "/LOG=`"$(Join-Path $LogDir 'PyCharm-2026.2.3-Install.log')`" /D=$PyCharmDir"
    [void](Invoke-Installer $PyCharmInstaller $pycharmArgs)
    if (-not (Test-Path -LiteralPath (Join-Path $PyCharmDir 'bin\pycharm64.exe'))) {
        throw "PyCharm install finished but '$PyCharmDir\bin\pycharm64.exe' is missing"
    }

    # --- 3. Firewall -------------------------------------------------------------------------
    Get-NetFirewallRule -Group $FirewallGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'PyCharm 2026.2.3' -Group $FirewallGroup `
        -Program (Join-Path $PyCharmDir 'bin\pycharm64.exe') -Direction Inbound `
        -Action $FirewallAction -Profile Any | Out-Null
    Write-Output "Firewall: inbound $FirewallAction rule added for pycharm64.exe"

    # --- 4. Per-user defaults via Active Setup ------------------------------------------------
    New-Item -ItemType Directory -Path $DefaultsDir -Force | Out-Null
    # Remove the script's earlier name from older installs of this package.
    Remove-Item -LiteralPath (Join-Path $DefaultsDir 'Set-PyCharmInterpreter.ps1') -Force -ErrorAction SilentlyContinue
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Set-PyCharmUserDefaults.ps1') -Destination $DefaultsScript -Force

    New-Item -Path $ActiveSetupKey -Force | Out-Null
    Set-ItemProperty -Path $ActiveSetupKey -Name '(default)' -Value 'PyCharm 2026.2 user defaults'
    Set-ItemProperty -Path $ActiveSetupKey -Name 'StubPath' -Value (
        "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -NonInteractive " +
        "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$DefaultsScript`"")
    Set-ItemProperty -Path $ActiveSetupKey -Name 'Version' -Value $ActiveSetupVersion
    Set-ItemProperty -Path $ActiveSetupKey -Name 'IsInstalled' -Value 1 -Type DWord

    # --- 5. Existing profiles, now -----------------------------------------------------------
    $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($entry in Get-ChildItem -Path $profileList) {
        # Local/domain accounts (S-1-5-21-*) and Entra ID accounts (S-1-12-1-*).
        if ($entry.PSChildName -notmatch '^S-1-(5-21|12-1)-') { continue }
        $profilePath = (Get-ItemProperty -Path $entry.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $profilePath) { continue }
        $roaming = Join-Path ([Environment]::ExpandEnvironmentVariables($profilePath)) 'AppData\Roaming'
        if (-not (Test-Path -LiteralPath $roaming)) { continue }
        # A signed-in user's registry hive is loaded under HKEY_USERS. For anyone else, Active
        # Setup sets the registry part at their next logon.
        $hive = "Registry::HKEY_USERS\$($entry.PSChildName)"
        $registryRoot = if (Test-Path -LiteralPath $hive) { $hive } else { '' }
        try {
            & $DefaultsScript -ConfigRoot $roaming -RegistryRoot $registryRoot -PythonExe $PythonExe -PythonVersion $PythonVersion
        } catch {
            Write-Warning "Could not configure PyCharm for '$profilePath': $($_.Exception.Message)"
        }
    }

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
