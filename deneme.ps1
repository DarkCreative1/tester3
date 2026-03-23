[CmdletBinding()]
param(
    [Parameter()]
    [switch]$BypassAdmin = $true
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-Spicetify {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += "--bypass-admin"
    }
    $spicetifyArgs += $Arguments

    & spicetify @spicetifyArgs
    return $LASTEXITCODE
}

function Invoke-SpicetifyWithOutput {
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $spicetifyArgs = @()
    if ($BypassAdmin) {
        $spicetifyArgs += "--bypass-admin"
    }
    $spicetifyArgs += $Arguments

    $output = (& spicetify @spicetifyArgs 2>&1 | Out-String).Trim()
    return @{
        Output   = $output
        ExitCode = $LASTEXITCODE
    }
}

Write-Host -Object 'Setting up...' -ForegroundColor 'Cyan'

if (-not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
    Write-Host -Object 'Spicetify not found.' -ForegroundColor 'Yellow'
    Write-Host -Object 'Installing it for you...' -ForegroundColor 'Cyan'

    $installParams = @{
        Uri             = 'https://raw.githubusercontent.com/spicetify/cli/main/install.ps1'
        UseBasicParsing = $true
    }

    Invoke-WebRequest @installParams | Invoke-Expression
}

try {
    $result = Invoke-SpicetifyWithOutput "path" "userdata"
    if ($result.ExitCode -ne 0) {
        Write-Host -Object "Error from Spicetify:" -ForegroundColor 'Red'
        Write-Host -Object $result.Output -ForegroundColor 'Red'
        return
    }

    $spiceUserDataPath = $result.Output
}
catch {
    Write-Host -Object "Error running Spicetify:" -ForegroundColor 'Red'
    Write-Host -Object $_.Exception.Message.Trim() -ForegroundColor 'Red'
    return
}

if (-not (Test-Path -Path $spiceUserDataPath -PathType Container -ErrorAction SilentlyContinue)) {
    $spiceUserDataPath = Join-Path $env:APPDATA 'spicetify'
}

$marketAppPath   = Join-Path $spiceUserDataPath 'CustomApps\marketplace'
$marketThemePath = Join-Path $spiceUserDataPath 'Themes\marketplace'

Invoke-Spicetify "path" "-s" | Out-Null
$isThemeInstalled = ($LASTEXITCODE -eq 0)

$currentTheme = (Invoke-SpicetifyWithOutput "config" "current_theme").Output.Trim()
$setTheme = $true

Write-Host -Object 'Removing and creating Marketplace folders...' -ForegroundColor 'Cyan'

try {
    Remove-Item -Path $marketAppPath, $marketThemePath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null

    New-Item -Path $marketAppPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
    New-Item -Path $marketThemePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
}
catch {
    Write-Host -Object "Error: $($_.Exception.Message.Trim())" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Downloading Marketplace...' -ForegroundColor 'Cyan'

$marketArchivePath = Join-Path $marketAppPath 'marketplace.zip'
$unpackedFolderPath = Join-Path $marketAppPath 'marketplace-dist'

$downloadParams = @{
    Uri             = 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip'
    UseBasicParsing = $true
    OutFile         = $marketArchivePath
}

try {
    Invoke-WebRequest @downloadParams
}
catch {
    Write-Host -Object "Error downloading Marketplace: $($_.Exception.Message.Trim())" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Unzipping and installing...' -ForegroundColor 'Cyan'

try {
    Expand-Archive -Path $marketArchivePath -DestinationPath $marketAppPath -Force

    if (Test-Path -Path $unpackedFolderPath) {
        Move-Item -Path (Join-Path $unpackedFolderPath '*') -Destination $marketAppPath -Force
        Remove-Item -Path $unpackedFolderPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -Path $marketArchivePath -Force -ErrorAction SilentlyContinue

    Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q" | Out-Null
    Invoke-Spicetify "config" "custom_apps" "marketplace" | Out-Null
    Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1" | Out-Null
}
catch {
    Write-Host -Object "Error during install: $($_.Exception.Message.Trim())" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Downloading placeholder theme...' -ForegroundColor 'Cyan'

$themeParams = @{
    Uri             = 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini'
    UseBasicParsing = $true
    OutFile         = (Join-Path $marketThemePath 'color.ini')
}

try {
    Invoke-WebRequest @themeParams
}
catch {
    Write-Host -Object "Error downloading placeholder theme: $($_.Exception.Message.Trim())" -ForegroundColor 'Red'
    return
}

Write-Host -Object 'Applying...' -ForegroundColor 'Cyan'

if ($isThemeInstalled -and ($currentTheme -ne 'marketplace')) {
    $Host.UI.RawUI.FlushInputBuffer()
    $choice = $Host.UI.PromptForChoice(
        'Local theme found',
        'Do you want to replace it with a placeholder to install themes from the Marketplace?',
        ('&Yes', '&No'),
        0
    )

    if ($choice -eq 1) {
        $setTheme = $false
    }
}

if ($setTheme) {
    Invoke-Spicetify "config" "current_theme" "marketplace" | Out-Null
}

Invoke-Spicetify "backup" | Out-Null
Invoke-Spicetify "apply" | Out-Null

Write-Host -Object 'Done!' -ForegroundColor 'Green'
Write-Host -Object 'If nothing has happened, check the messages above for errors'