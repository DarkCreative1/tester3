$ErrorActionPreference = "Stop"

Stop-Process -Name Spotify -Force -ErrorAction SilentlyContinue

Write-Host "Config dosyasi:" -ForegroundColor Cyan
spicetify -c

Write-Host "Mevcut config:" -ForegroundColor Cyan
spicetify config

$prefs = "$env:APPDATA\Spotify\prefs"
Write-Host "Beklenen prefs yolu: $prefs" -ForegroundColor Cyan

if (-not (Test-Path $prefs)) {
    Write-Host "HATA: Bu kullanicida prefs dosyasi yok." -ForegroundColor Red
    Write-Host "Spotify'i bu hesapta ac, giris yap, 60 saniye bekle; ya da scripti Spotify'i kullandigin hesapta calistir." -ForegroundColor Yellow
    exit 1
}

spicetify config prefs_path $prefs

Write-Host "Backup deneniyor..." -ForegroundColor Cyan
spicetify --bypass-admin backup
