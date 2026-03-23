[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$BypassAdmin = $true

function Invoke-Spicetify {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $argList = @()
    if ($BypassAdmin) { $argList += "--bypass-admin" }
    $argList += $Arguments

    Write-Host ("spicetify " + ($argList -join ' ')) -ForegroundColor DarkGray
    & spicetify @argList
    return $LASTEXITCODE
}

function Ensure-SpicetifyInstalled {
    if (-not (Get-Command spicetify -ErrorAction SilentlyContinue)) {
        Write-Host "Spicetify bulunamadi, kuruluyor..." -ForegroundColor Cyan
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/spicetify/cli/main/install.ps1" | Invoke-Expression
    }
}

function Stop-SpotifyNow {
    Get-Process Spotify -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}

function Assert-SpotifyReady {
    $prefsPath = Join-Path $env:APPDATA "Spotify\prefs"

    if (Get-AppxPackage *Spotify* -ErrorAction SilentlyContinue) {
        throw "Microsoft Store Spotify tespit edildi. Store surumu yerine Spotify'in normal masaustu surumunu kur."
    }

    if (-not (Test-Path $prefsPath)) {
        throw "prefs dosyasi bulunamadi: $prefsPath`nSpotify'i bu hesapta ac, giris yap, 60 saniye bekle; sonra tekrar dene."
    }

    spicetify config prefs_path $prefsPath | Out-Null
}

Write-Host "Kurulum baslatiliyor..." -ForegroundColor Cyan

Ensure-SpicetifyInstalled
Stop-SpotifyNow
Assert-SpotifyReady

$spiceUserDataPath = Join-Path $env:APPDATA "spicetify"
$marketAppPath     = Join-Path $spiceUserDataPath "CustomApps\marketplace"
$marketThemePath   = Join-Path $spiceUserDataPath "Themes\marketplace"
$marketZipPath     = Join-Path $marketAppPath "marketplace.zip"
$extractPath       = Join-Path $marketAppPath "extract"

Write-Host "Eski dosyalar temizleniyor..." -ForegroundColor Cyan
Remove-Item $marketAppPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $marketThemePath -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $marketAppPath -Force | Out-Null
New-Item -ItemType Directory -Path $marketThemePath -Force | Out-Null

Write-Host "Marketplace indiriliyor..." -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip" `
    -OutFile $marketZipPath

Write-Host "Arsiv aciliyor..." -ForegroundColor Cyan
Expand-Archive -Path $marketZipPath -DestinationPath $extractPath -Force
Get-ChildItem -Path $extractPath -Force | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $marketAppPath -Force
}
Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $marketZipPath -Force -ErrorAction SilentlyContinue

Write-Host "Theme dosyasi indiriliyor..." -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini" `
    -OutFile (Join-Path $marketThemePath "color.ini")

Write-Host "Config ayarlaniyor..." -ForegroundColor Cyan
Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q" | Out-Null
Invoke-Spicetify "config" "custom_apps" "marketplace" | Out-Null
Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1" | Out-Null
Invoke-Spicetify "config" "current_theme" "marketplace" | Out-Null

Stop-SpotifyNow

Write-Host "Backup + apply calisiyor..." -ForegroundColor Cyan
Invoke-Spicetify "backup" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "spicetify backup basarisiz oldu." }

Stop-SpotifyNow

Invoke-Spicetify "apply" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "spicetify apply basarisiz oldu." }

Write-Host "Tamamlandi." -ForegroundColor Green
