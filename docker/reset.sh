#!/usr/bin/env bash
# Nuke the AITK + DSDL lab and restart with a fresh Splunk container.
# Mirrors reset.ps1.
#
# Default (fast) wipes:
#   - the Splunk container
#   - splunk-var  (indexes, _internal logs, trial state)
#   - splunk-etc  (installed apps + DSDL saved config)
# ...then re-runs first-boot, re-installing AITK/PSC/DSDL from splunk-apps/
# via SPLUNK_APPS_URL. You'll re-do the DSDL Setup page once.
#
# Does NOT remove the DSDL golden image. Pass --containers to also remove
# leftover DSDL-spawned model containers (mltk-container-*).
#
# Usage:
#   ./docker/reset.sh             # fast reset (keeps BOTSv1 volume)
#   ./docker/reset.sh --full      # also wipe BOTSv1 volume (next setup re-copies ~6 GB)
#   ./docker/reset.sh --containers
#   ./docker/reset.sh --force     # skip confirmation

set -euo pipefail

CONTAINERS=0
FULL=0
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --containers) CONTAINERS=1 ;;
        --full)       FULL=1 ;;
        --force)      FORCE=1 ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
STATE_VOLUMES=(splunkaitk_splunk-etc splunkaitk_splunk-var)
BOTS_VOLUME=splunkaitk_splunk-botsv1

echo
echo "Splunk AITK + DSDL Lab — Reset"
echo "----------------------------------------"
echo "Compose file : $COMPOSE_FILE"
echo "Wipes        : container + splunk-etc + splunk-var (apps re-install on next boot)"
if [ "$FULL" -eq 1 ]; then echo "Also         : wiping BOTSv1 volume — next setup re-copies it (~6 GB)"
else                       echo "Keeps        : BOTSv1 volume (no 6 GB re-copy)"; fi
[ "$CONTAINERS" -eq 1 ] && echo "Also         : removing DSDL model containers (mltk-container-*)"
echo

if [ "$FORCE" -ne 1 ]; then
    read -rp "Continue? [y/N] " answer
    case "$answer" in [Yy]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

echo "==> Stopping Splunk container"
docker compose -f "$COMPOSE_FILE" down --remove-orphans

echo "==> Removing state volumes"
if [ "$FULL" -eq 1 ]; then
    docker volume rm "${STATE_VOLUMES[@]}" "$BOTS_VOLUME" 2>/dev/null || true
else
    docker volume rm "${STATE_VOLUMES[@]}" 2>/dev/null || true
fi

if [ "$CONTAINERS" -eq 1 ]; then
    echo "==> Removing leftover DSDL model containers"
    ids="$(docker ps -aq --filter name=mltk-container || true)"
    [ -n "$ids" ] && docker rm -f $ids 2>/dev/null || true
fi

echo "==> Starting fresh Splunk container"
docker compose -f "$COMPOSE_FILE" up -d

echo
echo "Splunk is booting + re-installing apps (~3-8 min on first boot)."
echo "  Web UI   : http://localhost:8000  (admin / see docker/.env)"
echo "  Tail log : docker logs -f splunk-aitk"
echo "Re-do the DSDL Setup page after healthy (Docker Host: unix://var/run/docker.sock)."
