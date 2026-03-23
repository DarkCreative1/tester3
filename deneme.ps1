[CmdletBinding()]
param(
    [switch]$BypassAdmin = $true
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-Spicetify {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $argsList = @()
    if ($BypassAdmin) {
        $argsList += "--bypass-admin"
    }
    $argsList += $Arguments

    Write-Host ("spicetify " + ($argsList -join ' ')) -ForegroundColor DarkGray
    & spicetify @argsList
    return $LASTEXITCODE
}

function Invoke-SpicetifyCapture {
    param(
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $argsList = @()
    if ($BypassAdmin) {
        $argsList += "--bypass-admin"
    }
    $argsList += $Arguments

    Write-Host ("spicetify " + ($argsList -join ' ')) -ForegroundColor DarkGray
    $output = & spicetify @argsList 2>&1 | Out-String
    return @{
        Output   = $output.Trim()
        ExitCode = $LASTEXITCODE
    }
}

function Stop-SpotifyProcesses {
    Write-Host 'Spotify kapatılıyor...' -ForegroundColor Cyan

    $spotifyProcesses = Get-Process -Name "Spotify" -ErrorAction SilentlyContinue
    if ($spotifyProcesses) {
        foreach ($proc in $spotifyProcesses) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Host "Spotify process kapatılamadı: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
        Start-Sleep -Seconds 2
    }
}

function Ensure-SpicetifyInstalled {
    if (-not (Get-Command -Name 'spicetify' -ErrorAction SilentlyContinue)) {
        Write-Host 'Spicetify bulunamadı, kuruluyor...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/spicetify/cli/main/install.ps1' -UseBasicParsing |
            Invoke-Expression
    }
}

function Get-SpicetifyUserDataPath {
    $result = Invoke-SpicetifyCapture "path" "userdata"

    if ($result.ExitCode -eq 0 -and $result.Output) {
        return $result.Output
    }

    $fallback = Join-Path $env:APPDATA 'spicetify'
    return $fallback
}

Write-Host 'Kurulum başlatılıyor...' -ForegroundColor Cyan

Ensure-SpicetifyInstalled

$spiceUserDataPath = Get-SpicetifyUserDataPath

if (-not (Test-Path $spiceUserDataPath)) {
    New-Item -Path $spiceUserDataPath -ItemType Directory -Force | Out-Null
}

$marketAppPath   = Join-Path $spiceUserDataPath 'CustomApps\marketplace'
$marketThemePath = Join-Path $spiceUserDataPath 'Themes\marketplace'
$marketZipPath   = Join-Path $marketAppPath 'marketplace.zip'
$extractPath     = Join-Path $marketAppPath 'marketplace-dist'

Write-Host 'Eski Marketplace dosyaları temizleniyor...' -ForegroundColor Cyan
Remove-Item -Path $marketAppPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $marketThemePath -Recurse -Force -ErrorAction SilentlyContinue

New-Item -Path $marketAppPath -ItemType Directory -Force | Out-Null
New-Item -Path $marketThemePath -ItemType Directory -Force | Out-Null

Write-Host 'Marketplace indiriliyor...' -ForegroundColor Cyan
Invoke-WebRequest `
    -Uri 'https://github.com/spicetify/marketplace/releases/latest/download/marketplace.zip' `
    -UseBasicParsing `
    -OutFile $marketZipPath

Write-Host 'Zip açılıyor...' -ForegroundColor Cyan
Expand-Archive -Path $marketZipPath -DestinationPath $extractPath -Force

$innerItems = Get-ChildItem -Path $extractPath -Force -ErrorAction SilentlyContinue
if ($innerItems) {
    Move-Item -Path (Join-Path $extractPath '*') -Destination $marketAppPath -Force
}

Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $marketZipPath -Force -ErrorAction SilentlyContinue

Write-Host 'Placeholder theme indiriliyor...' -ForegroundColor Cyan
Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/spicetify/marketplace/main/resources/color.ini' `
    -UseBasicParsing `
    -OutFile (Join-Path $marketThemePath 'color.ini')

Write-Host 'Spicetify config ayarlanıyor...' -ForegroundColor Cyan
Invoke-Spicetify "config" "custom_apps" "spicetify-marketplace-" "-q" | Out-Null
Invoke-Spicetify "config" "custom_apps" "marketplace" | Out-Null
Invoke-Spicetify "config" "inject_css" "1" "replace_colors" "1" | Out-Null
Invoke-Spicetify "config" "current_theme" "marketplace" | Out-Null

Stop-SpotifyProcesses

Write-Host 'Backup oluşturuluyor...' -ForegroundColor Cyan
$backupResult = Invoke-SpicetifyCapture "backup"
Write-Host $backupResult.Output

if ($backupResult.ExitCode -ne 0) {
    Write-Host 'Backup başarısız oldu.' -ForegroundColor Red
    exit 1
}

Stop-SpotifyProcesses

Write-Host 'Apply çalıştırılıyor...' -ForegroundColor Cyan
$applyResult = Invoke-SpicetifyCapture "apply"
Write-Host $applyResult.Output

if ($applyResult.ExitCode -ne 0) {
    Write-Host 'Apply başarısız oldu.' -ForegroundColor Red
    exit 1
}

Write-Host 'Kurulum tamamlandı.' -ForegroundColor Green
Write-Host 'Şimdi Spotify açıp kontrol et.' -ForegroundColor Green
