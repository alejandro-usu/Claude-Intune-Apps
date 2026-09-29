<#
.SYNOPSIS
    Intune custom detection script for <APP NAME> <VERSION>.

.DESCRIPTION
    Intune treats the app as installed when this script writes to stdout and exits 0.
    Check for the exact version this package installs, so Intune reinstalls older versions.
    Set "Run script as 32-bit process on 64-bit clients" to No.
#>
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }

try {
    # Example: check a file's version.
    $exe = Join-Path $programFiles '<Vendor>\<App>\<app>.exe'
    if (-not (Test-Path -LiteralPath $exe)) { exit 1 }
    if ((Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -ne '<VERSION>') { exit 1 }

    Write-Output "<APP NAME> <VERSION> detected"
    exit 0
} catch {
    exit 1
}
