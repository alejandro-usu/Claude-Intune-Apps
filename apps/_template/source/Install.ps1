<#
.SYNOPSIS
    Intune Win32 install script for <APP NAME> <VERSION>.

.DESCRIPTION
    Runs as SYSTEM. Replace the example install step with the app's own silent install.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<APP-FOLDER>-Install.log
#>
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$AppLogName = '<APP-FOLDER>'
$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "$AppLogName-Install.log") -Append | Out-Null

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
    # Example for an MSI listed in app.json "downloads":
    #   $msi = Join-Path $PSScriptRoot 'example-1.2.3-x64.msi'
    #   $code = Invoke-Installer "$env:SystemRoot\System32\msiexec.exe" `
    #       "/i `"$msi`" /qn /norestart /l*v `"$(Join-Path $LogDir "$AppLogName-msi.log")`"" @(0, 3010)
    #   if ($code -eq 3010) { $exitCode = 3010 }
    #
    # Example for an EXE installer:
    #   [void](Invoke-Installer (Join-Path $PSScriptRoot 'example-setup.exe') '/S')
    throw 'Install.ps1 is still the template; replace this line with the install steps.'

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
