<#
.SYNOPSIS
    Intune Win32 uninstall script for <APP NAME> <VERSION>.

.DESCRIPTION
    Runs as SYSTEM. Replace the example uninstall step with the app's own silent uninstall.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<APP-FOLDER>-Uninstall.log
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$AppLogName = '<APP-FOLDER>'
$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "$AppLogName-Uninstall.log") -Append | Out-Null

$exitCode = 0
try {
    # Example for an MSI (use the product code from the MSI's Property table):
    #   $process = Start-Process "$env:SystemRoot\System32\msiexec.exe" -Wait -PassThru -ArgumentList (
    #       "/x {00000000-0000-0000-0000-000000000000} /qn /norestart")
    #   if ($process.ExitCode -eq 3010) { $exitCode = 3010 }
    #   elseif ($process.ExitCode -notin 0, 1605) { throw "msiexec failed with exit code $($process.ExitCode)" }
    throw 'Uninstall.ps1 is still the template; replace this line with the uninstall steps.'

    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
