# Nuke the AITK + DSDL lab and restart with a fresh Splunk container.
# Use this when:
#   - Trial license expires (60 days from first boot)
#   - You want a clean Splunk (re-installs the 3 apps from splunk-apps\)
#   - The container is in a weird state
#
# Default (fast) wipes:
#   - the Splunk container
#   - splunk-var  (indexes, _internal logs, trial state)
#   - splunk-etc  (installed apps + DSDL saved config)
# ...then re-runs first-boot, which re-installs AITK/PSC/DSDL from
# splunk-apps\ via SPLUNK_APPS_URL. You'll re-do the DSDL Setup page once.
#
# This does NOT remove the DSDL golden image or any DSDL-spawned model
# containers - those live on the host Docker. Pass -Containers to also
# stop+remove leftover mltk-container-* model containers.
#
# Usage:
#   .\docker\reset.ps1              # fast reset (keeps BOTSv1 volume)
#   .\docker\reset.ps1 -Full        # also wipe BOTSv1 volume (next setup re-copies ~6 GB)
#   .\docker\reset.ps1 -Containers  # also clean up DSDL model containers
#   .\docker\reset.ps1 -Force       # skip confirmation

param(
    [switch]$Containers,
    [switch]$Full,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$composeFile  = Join-Path $PSScriptRoot "docker-compose.yml"
$stateVolumes = @("splunkaitk_splunk-etc", "splunkaitk_splunk-var")
$botsVolume   = "splunkaitk_splunk-botsv1"

Write-Host ""
Write-Host "Splunk AITK + DSDL Lab - Reset" -ForegroundColor Cyan
Write-Host "----------------------------------------"
Write-Host "Compose file : $composeFile"
Write-Host "Wipes        : container + splunk-etc + splunk-var (apps re-install on next boot)"
if ($Full) {
    Write-Host "Also         : wiping BOTSv1 volume - next setup re-copies it (~6 GB)" -ForegroundColor Yellow
} else {
    Write-Host "Keeps        : BOTSv1 volume (no 6 GB re-copy)"
}
if ($Containers) { Write-Host "Also         : removing DSDL model containers (mltk-container-*)" -ForegroundColor Yellow }
Write-Host ""

if (-not $Force) {
    $answer = Read-Host "Continue? [y/N]"
    if ($answer -notmatch '^[Yy]') { Write-Host "Aborted." -ForegroundColor Yellow; exit 0 }
}

Write-Host "==> Stopping Splunk container" -ForegroundColor Green
docker compose -f $composeFile down --remove-orphans

Write-Host "==> Removing state volumes" -ForegroundColor Green
if ($Full) { docker volume rm ($stateVolumes + $botsVolume) 2>$null }
else       { docker volume rm $stateVolumes 2>$null }

if ($Containers) {
    Write-Host "==> Removing leftover DSDL model containers" -ForegroundColor Green
    $ids = docker ps -aq --filter "name=mltk-container"
    if ($ids) { docker rm -f $ids 2>$null }
}

Write-Host "==> Starting fresh Splunk container" -ForegroundColor Green
docker compose -f $composeFile up -d

Write-Host ""
Write-Host "Splunk is booting + re-installing apps (~3-8 min on first boot)." -ForegroundColor Cyan
Write-Host "  Web UI   : http://localhost:8000  (admin / see docker\.env)"
Write-Host "  Tail log : docker logs -f splunk-aitk"
Write-Host "Re-do the DSDL Setup page after it's healthy (Docker Host: unix://var/run/docker.sock)."
