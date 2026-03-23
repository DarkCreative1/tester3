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
    if ($BypassAdmin) {
        $argList += "--bypass-admin"
    }
    $argList += $Arguments

    Write-Host ("spicetify " + ($argList -join ' ')) -ForegroundColor DarkGray
    & spicetify @argList
    return $LASTEXITCODE
}

function Invoke-SpicetifyCapture {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $argList = @()
    if ($BypassAdmin) {
        $argList += "--bypass-admin"
    }
    $argList += $Arguments

    Write-Host ("spicetify " + ($argList -join ' ')) -ForegroundColor DarkGray
    $output = & spicetify @argList 2>&1 | Out-String
    return @{
        Output   = $output.Trim()
        ExitCode = $LASTEXITCODE
    }
}

function Stop-SpotifyProcesses {
    $procs = Get-Process -Name "Spotify" -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Spotify kapatılıyor..." -ForegroundColor Cyan
        foreach ($proc in $procs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Host "Spotify kapatılamadı: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        Start-Sleep -Seconds 3
    }
}

function Ensure-SpicetifyInstalled {
    if (-not (Get-Command spicetify -ErrorAction SilentlyContinue)) {
        Write-Host "Spicetify bulunamadı, kuruluyor..." -ForegroundColor Cyan
        Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/spicetify/cli/main/install.ps1" | Invoke-Expression
    }
}

function Get-SpicePath {
    $result = Invoke-SpicetifyCapture "path" "userdata"
    if ($result.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($result.Output)) {
        return $result.Output
    }
    return (Join-Path $env:APPDATA "spicetify")
}

Write-Host "Kurulum başlatılıyor..." -ForegroundColor Cyan

Ensure-SpicetifyInstalled

$spiceUserDataPath = Get-SpicePath
if (-not (Test-Path $spiceUserDataPath)) {
    New-Item -ItemType Directory -Path $spiceUserDataPath -Force | Out-Null
}

$marketAppPath   = Join-Path $spiceUserDataPath "CustomApps\marketplace"
$marketThemePath = Join-Path $spiceUserDataPath "Themes\marketplace"
$marketZipPath   = Join-Path $marketAppPath "marketplace.zip"
$extractPath     = Join-Path $marketAppPath "extract"

Write-Host "Eski dosyalar temizleniyor..." -ForegroundColor Cyan
Remove-Item $marketAppPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $marketThemePath -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $marketAppPath -Force | Out-Null
New-Item -ItemType Directory -Path $marketThemePath -Force | Out-Null

Write-Host "Marketplace indiriliyor..." -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip" `
    -OutFile $marketZipPath

Write-Host "Arşiv açılıyor..." -ForegroundColor Cyan
Expand-Archive -Path $marketZipPath -DestinationPath $extractPath -Force

Get-ChildItem -Path $extractPath -Force | ForEach-Object {
    Move-Item -Path $_.FullName -Destination $marketAppPath -Force
}

Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $marketZipPath -Force -ErrorAction SilentlyContinue

Write-Host "Theme dosyası indiriliyor..." -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing `
    -Uri "https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini" `
    -OutFile (Join-Path $marketThemePath "color.ini")

Write-Host "Config ayarlanıyor..." -ForegroundColor Cyan
Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q" | Out-Null
Invoke-Spicetify "config" "custom_apps" "marketplace" | Out-Null
Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1" | Out-Null
Invoke-Spicetify "config" "current_theme" "marketplace" | Out-Null

Stop-SpotifyProcesses

Write-Host "Backup alınıyor..." -ForegroundColor Cyan
$backup = Invoke-SpicetifyCapture "backup"
if ($backup.Output) { Write-Host $backup.Output }
if ($backup.ExitCode -ne 0) {
    Write-Host "Backup başarısız." -ForegroundColor Red
    exit 1
}

Stop-SpotifyProcesses

Write-Host "Apply yapılıyor..." -ForegroundColor Cyan
$apply = Invoke-SpicetifyCapture "apply"
if ($apply.Output) { Write-Host $apply.Output }
if ($apply.ExitCode -ne 0) {
    Write-Host "Apply başarısız." -ForegroundColor Red
    exit 1
}

Write-Host "Tamamlandı." -ForegroundColor Green
