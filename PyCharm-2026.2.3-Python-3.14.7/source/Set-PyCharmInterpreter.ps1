<#
.SYNOPSIS
    Registers Python 3.14 as an interpreter in PyCharm 2026.2 and makes it the default
    for new projects, for one user profile.

.DESCRIPTION
    PyCharm keeps interpreter settings per user, in %APPDATA%\JetBrains\PyCharm2026.2\options:

      jdk.table.xml        the list of interpreters (SDKs) PyCharm knows about
      project.default.xml  settings for new projects, including their interpreter
      pySdk.xml            the base interpreter the New Project wizard uses for a new venv

    This script adds (or reuses) a "Python SDK" entry for the given python.exe and points
    the other two files at it. Existing content in all three files is kept.

    If PyCharm 2026.2 has never been started for this user, its first launch would normally
    import settings from an older PyCharm version. PyCharm skips any file that already exists
    in the new config folder during that import, so this script starts from the older version's
    copy of each file instead. That keeps the user's older interpreters and new-project
    defaults as well as adding Python 3.14. The files PyCharm uses to tell whether a config
    folder is already set up (options\other.xml, ide.general.xml, options.xml) are never
    created here, so the import still runs for everything else.

    The same script runs in two ways:
      - as SYSTEM from Install.ps1, once for each existing profile (-ConfigRoot given)
      - as the user from Active Setup at each user's next logon (no parameters)

    It is safe to run more than once.

.PARAMETER ConfigRoot
    The user's roaming AppData folder. Defaults to $env:APPDATA.
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = $env:APPDATA,
    [string]$PythonExe = "$env:ProgramFiles\Python314\python.exe",
    [string]$PythonVersion = '3.14.7',
    [string]$SdkName = 'Python 3.14',
    [string]$ConfigDirName = 'PyCharm2026.2'
)

$ErrorActionPreference = 'Stop'

$SdkType = 'Python SDK'
# Files whose presence tells PyCharm the config folder is already set up (InitialConfigImportState.OPTIONS).
$ConfigMarkers = @('options\other.xml', 'options\ide.general.xml', 'options\options.xml')

function Get-NormalizedPath([string]$Path) {
    if (-not $Path) { return '' }
    return $Path.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function ConvertTo-FileUrl([string]$Path) {
    return 'file://' + $Path.Replace('\', '/')
}

function Read-XmlOrNew([string]$Path) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    if (Test-Path -LiteralPath $Path) {
        try {
            $doc.Load($Path)
            return $doc
        } catch {
            Write-Warning "Could not parse '$Path', replacing it: $($_.Exception.Message)"
            Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force
            $doc = New-Object System.Xml.XmlDocument
        }
    }
    [void]$doc.AppendChild($doc.CreateElement('application'))
    return $doc
}

function Save-Xml([System.Xml.XmlDocument]$Doc, [string]$Path) {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.OmitXmlDeclaration = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Doc.Save($writer) } finally { $writer.Close() }
}

function Get-Component([System.Xml.XmlDocument]$Doc, [string]$Name) {
    $component = $Doc.DocumentElement.SelectSingleNode("component[@name='$Name']")
    if (-not $component) {
        $component = $Doc.CreateElement('component')
        $component.SetAttribute('name', $Name)
        [void]$Doc.DocumentElement.AppendChild($component)
    }
    return $component
}

function Add-Element([System.Xml.XmlNode]$Parent, [string]$Name, [hashtable]$Attributes = @{}) {
    $element = $Parent.OwnerDocument.CreateElement($Name)
    foreach ($key in $Attributes.Keys) { $element.SetAttribute($key, $Attributes[$key]) }
    [void]$Parent.AppendChild($element)
    return $element
}

function Find-PreviousOptionsFile([string]$JetBrainsDir, [string]$FileName) {
    # Newest older PyCharm / PyCharm CE config folder that has this file.
    $candidates = @()
    foreach ($dir in Get-ChildItem -LiteralPath $JetBrainsDir -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -ne $ConfigDirName -and $dir.Name -match '^PyCharm(CE)?(\d{4})\.(\d+)$') {
            $candidates += [pscustomobject]@{
                Dir     = $dir.FullName
                Version = [version]"$($Matches[2]).$($Matches[3])"
            }
        }
    }
    foreach ($candidate in ($candidates | Sort-Object Version -Descending)) {
        $file = Join-Path $candidate.Dir "options\$FileName"
        if (Test-Path -LiteralPath $file) { return $file }
    }
    return $null
}

if (-not $ConfigRoot) { throw 'No ConfigRoot given and APPDATA is not set.' }
if (-not (Test-Path -LiteralPath $PythonExe)) {
    Write-Warning "Python not found at '$PythonExe'; nothing to configure."
    return
}

$jetBrainsDir = Join-Path $ConfigRoot 'JetBrains'
$configDir = Join-Path $jetBrainsDir $ConfigDirName
$optionsDir = Join-Path $configDir 'options'
$isFreshConfig = -not ($ConfigMarkers | Where-Object { Test-Path -LiteralPath (Join-Path $configDir $_) })

New-Item -ItemType Directory -Path $optionsDir -Force | Out-Null

foreach ($fileName in 'jdk.table.xml', 'project.default.xml', 'pySdk.xml') {
    $target = Join-Path $optionsDir $fileName
    if ($isFreshConfig -and -not (Test-Path -LiteralPath $target)) {
        $previous = Find-PreviousOptionsFile $jetBrainsDir $fileName
        if ($previous) {
            Write-Verbose "Seeding $fileName from $previous"
            Copy-Item -LiteralPath $previous -Destination $target
        }
    }
}

# --- jdk.table.xml: make sure there is an SDK entry for this python.exe -----------------------
$jdkTablePath = Join-Path $optionsDir 'jdk.table.xml'
$jdkTable = Read-XmlOrNew $jdkTablePath
$sdkTable = Get-Component $jdkTable 'ProjectJdkTable'

$wantedHome = Get-NormalizedPath $PythonExe
$existing = $null
$namesInUse = @{}
foreach ($jdk in $sdkTable.SelectNodes('jdk')) {
    $name = $jdk.SelectSingleNode('name/@value').Value
    $namesInUse[$name] = $true
    $type = $jdk.SelectSingleNode('type/@value').Value
    $homePath = $jdk.SelectSingleNode('homePath/@value').Value
    if ($type -eq $SdkType -and (Get-NormalizedPath $homePath) -eq $wantedHome) { $existing = $jdk }
}

if ($existing) {
    $SdkName = $existing.SelectSingleNode('name/@value').Value
    Write-Verbose "Reusing existing SDK '$SdkName'"
} else {
    $baseName = $SdkName
    $suffix = 1
    while ($namesInUse.ContainsKey($SdkName)) {
        $suffix++
        $SdkName = "$baseName ($suffix)"
    }

    $pythonHome = Split-Path -Parent $PythonExe
    $jdk = Add-Element $sdkTable 'jdk' @{ version = '2' }
    [void](Add-Element $jdk 'name' @{ value = $SdkName })
    [void](Add-Element $jdk 'type' @{ value = $SdkType })
    [void](Add-Element $jdk 'version' @{ value = "Python $PythonVersion" })
    [void](Add-Element $jdk 'homePath' @{ value = $PythonExe })
    $roots = Add-Element $jdk 'roots'
    $classPath = Add-Element (Add-Element $roots 'classPath') 'root' @{ type = 'composite' }
    foreach ($dir in 'DLLs', 'Lib', '', 'Lib\site-packages') {
        $path = if ($dir) { Join-Path $pythonHome $dir } else { $pythonHome }
        [void](Add-Element $classPath 'root' @{ url = (ConvertTo-FileUrl $path); type = 'simple' })
    }
    [void](Add-Element (Add-Element $roots 'sourcePath') 'root' @{ type = 'composite' })
    $additional = Add-Element $jdk 'additional' @{ SDK_UUID = [guid]::NewGuid().ToString() }
    [void](Add-Element $additional 'setting' @{ name = 'FLAVOR_ID'; value = 'WinPythonSdkFlavor' })
    [void](Add-Element $additional 'setting' @{ name = 'FLAVOR_DATA'; value = '{}' })
    Write-Verbose "Added SDK '$SdkName'"
}
Save-Xml $jdkTable $jdkTablePath

# --- project.default.xml: interpreter for new projects -----------------------------------------
$defaultProjectPath = Join-Path $optionsDir 'project.default.xml'
$defaultProject = Read-XmlOrNew $defaultProjectPath
$projectManager = Get-Component $defaultProject 'ProjectManager'
$template = $projectManager.SelectSingleNode('defaultProject')
if (-not $template) { $template = Add-Element $projectManager 'defaultProject' }
$rootManager = $template.SelectSingleNode("component[@name='ProjectRootManager']")
if (-not $rootManager) { $rootManager = Add-Element $template 'component' @{ name = 'ProjectRootManager' } }
$rootManager.SetAttribute('version', '2')
$rootManager.SetAttribute('project-jdk-name', $SdkName)
$rootManager.SetAttribute('project-jdk-type', $SdkType)
Save-Xml $defaultProject $defaultProjectPath

# --- pySdk.xml: base interpreter the New Project wizard picks for a new virtualenv -------------
$pySdkPath = Join-Path $optionsDir 'pySdk.xml'
$pySdk = Read-XmlOrNew $pySdkPath
$pySdkSettings = Get-Component $pySdk 'PySdkSettings'
$option = $pySdkSettings.SelectSingleNode("option[@name='PREFERRED_VIRTUALENV_BASE_SDK']")
if (-not $option) { $option = Add-Element $pySdkSettings 'option' @{ name = 'PREFERRED_VIRTUALENV_BASE_SDK' } }
$option.SetAttribute('value', $PythonExe)
Save-Xml $pySdk $pySdkPath

Write-Output "PyCharm default interpreter set to '$SdkName' ($PythonExe) in $optionsDir"
