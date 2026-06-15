#!/usr/bin/env bash
# One-shot bootstrap for the Splunk AITK + DSDL POC lab. Mirrors setup.ps1.
#
# Unlike the BOTS lab, the three Splunk apps this POC needs live on
# Splunkbase BEHIND A LOGIN, so they cannot be auto-downloaded. You stage
# them once in splunk-apps/ (see splunk-apps/README.md), then this script:
#   1. verifies Docker is running
#   2. discovers the PSC add-on + AITK/MLTK app + DSDL app in splunk-apps/
#   3. writes docker/.env so Splunk auto-installs them (PSC -> MLTK -> DSDL)
#      at first boot via SPLUNK_APPS_URL
#   4. pre-pulls the DSDL "golden image" container (skip with --skip-pull)
#   4b. populates this project's OWN BOTSv1 volume — uses bots-data/botsv1/
#       if present, else downloads the ~6 GB .tgz here (self-contained; never
#       reads from Splunk-Environment-Lab). Skip with --skip-bots.
#   5. brings Splunk up and waits for healthy
#   6. prints the exact values to enter on the DSDL Setup page
#
# Usage:
#   ./setup.sh
#   ./setup.sh --skip-pull
#   ./setup.sh --skip-bots                 # set up without BOTSv1
#   ./setup.sh --skip-download             # use a .tgz already in bots-data/botsv1/
#   ./setup.sh --url-v1 https://.../botsv1_data_set.tgz
#   ./setup.sh --golden-image splunk/mltk-container-golden-cpu:5.2.3 --force

set -euo pipefail

# Git Bash on Windows mangles Unix paths passed to docker.exe; disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

PASSWORD="p@ssw0rd"
GOLDEN_IMAGE="splunk/mltk-container-golden-cpu:5.2.3"
BOTS_URL="https://s3.amazonaws.com/botsdataset/botsv1/splunk-pre-indexed/botsv1_data_set.tgz"
SKIP_PULL=0
SKIP_BOTS=0
SKIP_DOWNLOAD=0
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --password)      PASSWORD="$2"; shift 2 ;;
        --golden-image)  GOLDEN_IMAGE="$2"; shift 2 ;;
        --url-v1)        BOTS_URL="$2"; shift 2 ;;
        --skip-pull)     SKIP_PULL=1; shift ;;
        --skip-bots)     SKIP_BOTS=1; shift ;;
        --skip-download) SKIP_DOWNLOAD=1; shift ;;
        --force)         FORCE=1; shift ;;
        -h|--help)       sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker/docker-compose.yml"
APPS_DIR="$REPO_ROOT/splunk-apps"
ENV_FILE="$REPO_ROOT/docker/.env"
CONTAINER="splunk-aitk"
BOTS_VOLUME="splunkaitk_splunk-botsv1"
SPLUNK_UID=41812

step() { echo; echo "==> $*"; }
info() { echo "    $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

to_winpath() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) cygpath -w "$1" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# --- 1. Pre-flight ---------------------------------------------------------
step "Pre-flight checks"
command -v docker >/dev/null 2>&1 || die "'docker' not found on PATH."
docker info >/dev/null 2>&1 || die "Docker daemon not reachable. Start Docker Desktop / dockerd and re-run."
info "docker daemon reachable"

# --- 2. Discover the three Splunkbase packages -----------------------------
# Splunkbase filenames are versioned, so match by pattern. PSC is
# platform-specific: stage the LINUX 64-bit build for the amd64 container.
step "Locating staged apps in splunk-apps/"
[ -d "$APPS_DIR" ] || die "splunk-apps/ folder missing. See splunk-apps/README.md."

# find_app <label> <exclude-glob-or-=> <include-glob1> [include-glob2 ...]
# Scans every archive type we might get: Splunkbase serves .tgz / .spl (gzipped
# tar), some mirrors hand out .tar.gz, and browsers (Safari especially) often
# auto-expand a downloaded .tgz into a bare .tar — so we accept all of them and
# normalize the format later (see ensure_installable). Matches any include glob.
find_app() {
    local label="$1" exc="$2"; shift 2
    local hit="" f n g
    for f in "$APPS_DIR"/*.tgz "$APPS_DIR"/*.spl "$APPS_DIR"/*.tar.gz \
             "$APPS_DIR"/*.tar "$APPS_DIR"/*.zip; do
        [ -e "$f" ] || continue
        n="$(basename "$f" | tr '[:upper:]' '[:lower:]')"
        if [ "$exc" != "=" ]; then case "$n" in $exc) continue ;; esac; fi
        for g in "$@"; do
            case "$n" in
                $g) [ -z "$hit" ] && hit="$(basename "$f")"; break ;;
            esac
        done
    done
    [ -n "$hit" ] || die "Could not find the $label package (.tgz/.spl/.tar.gz/.tar/.zip) in splunk-apps/. See splunk-apps/README.md."
    printf '%s\n' "$hit"
}

# is_gzip <basename> — true if the file starts with the gzip magic bytes.
is_gzip() { [ "$(head -c2 "$APPS_DIR/$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "1f8b" ]; }

# ensure_installable <basename> -> echoes a basename Splunk's boot-time install
# can consume (a gzipped-tar package). Already gzip-compressed (.tgz/.spl/.tar.gz)
# or a .zip is passed through; a bare, uncompressed .tar (e.g. a browser expanded
# the .tgz) is re-gzipped into a .tgz. Progress goes to stderr so this is safe
# inside $(...).
ensure_installable() {
    local base="$1"
    is_gzip "$base" && { printf '%s\n' "$base"; return; }
    case "$base" in *.zip) printf '%s\n' "$base"; return ;; esac
    if tar -tf "$APPS_DIR/$base" >/dev/null 2>&1; then
        local out="${base%.*}.tgz"
        echo "    normalizing $base -> $out (re-compressing uncompressed tar)" >&2
        gzip -c "$APPS_DIR/$base" > "$APPS_DIR/$out" || die "failed to gzip $base"
        printf '%s\n' "$out"; return
    fi
    die "$base is neither a gzip package, a tar, nor a zip. Re-download from Splunkbase (.tgz/.spl)."
}

# AITK is now named "splunk-ai-toolkit" (was machine-learning-toolkit); accept both.
PSC="$(find_app  'Python for Scientific Computing (Linux 64-bit)' '*windows*' '*scientific-computing*linux*')"
MLTK="$(find_app 'AITK / Machine Learning Toolkit'                '='        '*ai-toolkit*' '*machine-learning-toolkit*')"
DSDL="$(find_app 'DSDL (Data Science and Deep Learning)'          '='        '*deep-learning*' '*data-science*')"

# Re-compress anything a browser left uncompressed so the install never fails.
PSC="$(ensure_installable "$PSC")"
MLTK="$(ensure_installable "$MLTK")"
DSDL="$(ensure_installable "$DSDL")"

info "PSC  : $PSC"
info "AITK : $MLTK"
info "DSDL : $DSDL"

# --- 3. Write docker/.env --------------------------------------------------
APPS_URL="/tmp/apps/$PSC,/tmp/apps/$MLTK,/tmp/apps/$DSDL"
step "Writing docker/.env"
cat > "$ENV_FILE" <<EOF
# Generated by setup.sh — do not commit (gitignored).
SPLUNK_PASSWORD=$PASSWORD
SPLUNK_HEC_TOKEN=aitk-hec-token-CHANGE-ME
SPLUNK_APPS_URL=$APPS_URL
GOLDEN_IMAGE=$GOLDEN_IMAGE
EOF
info "SPLUNK_APPS_URL=$APPS_URL"

# --- 4. Pre-pull the DSDL golden image -------------------------------------
if [ "$SKIP_PULL" -eq 1 ]; then
    info "Skipping golden-image pull (--skip-pull)."
else
    step "Pulling DSDL golden image: $GOLDEN_IMAGE (a few GB, one-time)"
    docker pull "$GOLDEN_IMAGE" || info "WARNING: pull failed — DSDL can pull it later. Continuing."
fi

# --- 4b. Populate this project's OWN BOTSv1 volume -------------------------
# Fully self-contained — this project keeps its own copy under
# bots-data/botsv1/ and never reads from Splunk-Environment-Lab. Source
# preference:
#   1. this repo's bots-data/botsv1/         (if already extracted)
#   2. a local .tgz in bots-data/botsv1/     (extracted on the fly)
#   3. download the .tgz (~6 GB, resumable)  (unless --skip-download)
bots_volume_has_data() {
    docker volume inspect "$BOTS_VOLUME" >/dev/null 2>&1 || return 1
    docker run --rm -v "$BOTS_VOLUME:/c" alpine test -d /c/default >/dev/null 2>&1
}

if [ "$SKIP_BOTS" -eq 1 ]; then
    info "Skipping BOTSv1 population (--skip-bots)."
elif bots_volume_has_data && [ "$FORCE" -ne 1 ]; then
    step "BOTSv1 volume already populated — skipping (re-run with --force to repopulate)"
else
    step "Preparing this project's BOTSv1 volume ($BOTS_VOLUME)"
    OWN_DIR="$REPO_ROOT/bots-data/botsv1"
    mkdir -p "$OWN_DIR"
    SRC=""
    if [ -d "$OWN_DIR/default" ]; then
        SRC="$OWN_DIR"; info "source: bots-data/botsv1/ (already extracted)"
    else
        TGZ="$(find "$OWN_DIR" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.tar.gz' \) 2>/dev/null | head -n1)"
        if [ -z "$TGZ" ]; then
            if [ "$SKIP_DOWNLOAD" -eq 1 ]; then
                die "No BOTSv1 data in $OWN_DIR and --skip-download set. Drop botsv1_data_set.tgz there, or drop --skip-download."
            fi
            TGZ="$OWN_DIR/botsv1_data_set.tgz"
            step "Downloading BOTSv1 (~6 GB, resumable) into bots-data/botsv1/"
            info "$BOTS_URL"
            curl -L --fail -C - --progress-bar -o "$TGZ" "$BOTS_URL"
        fi
        step "Validating + extracting $(basename "$TGZ") into bots-data/botsv1/"
        tar -tzf "$TGZ" >/dev/null 2>&1 || die "'$TGZ' is not a valid gzipped tar — delete it and re-run."
        tar -xzf "$TGZ" -C "$OWN_DIR" --strip-components 1
        SRC="$OWN_DIR"
    fi

    if bots_volume_has_data && [ "$FORCE" -eq 1 ]; then
        info "wiping volume (--force)"
        docker compose -f "$(to_winpath "$COMPOSE_FILE")" down >/dev/null 2>&1 || true
        docker volume rm "$BOTS_VOLUME" >/dev/null 2>&1 || true
    fi

    step "Copying BOTSv1 into $BOTS_VOLUME (one-time, a few GB)"
    docker run --rm \
        -v "$(to_winpath "$SRC"):/src:ro" \
        -v "$BOTS_VOLUME:/dst" \
        alpine sh -c "set -e; cp -a /src/. /dst/ && rm -f /dst/*.tgz && chown -R ${SPLUNK_UID}:${SPLUNK_UID} /dst && du -sh /dst"
    info "BOTSv1 volume populated"
fi

# --- 5. Bring Splunk up ----------------------------------------------------
step "Starting Splunk container"
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    existing_project="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$CONTAINER" 2>/dev/null || true)"
    if [ -n "$existing_project" ] && [ "$existing_project" != "splunkaitk" ]; then
        info "Removing existing standalone $CONTAINER so compose can recreate it under the splunkaitk stack"
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
fi
if [ "$FORCE" -eq 1 ]; then
    docker compose -f "$(to_winpath "$COMPOSE_FILE")" up -d --force-recreate
else
    docker compose -f "$(to_winpath "$COMPOSE_FILE")" up -d
fi

# --- 6. Wait for healthy ---------------------------------------------------
step "Waiting for Splunk to become healthy (first boot installs 3 apps — up to ~8 min)"
deadline=$(( $(date +%s) + 480 ))
last=""
while [ "$(date +%s)" -lt "$deadline" ]; do
    status="$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo starting)"
    [ "$status" = "healthy" ] && break
    if [ "$status" != "$last" ]; then info "status: $status"; last="$status"; fi
    sleep 5
done
[ "${status:-}" = "healthy" ] || info "WARNING: not healthy yet — check: docker logs -f $CONTAINER"

# --- 7. Verify apps + print DSDL setup values ------------------------------
step "Verifying installed apps"
for app in Splunk_ML_Toolkit mltk-container Splunk_SA_Scientific_Python_linux_x86_64; do
    code="$(docker exec "$CONTAINER" curl -ks -o /dev/null -w '%{http_code}' \
        -u "admin:$PASSWORD" "https://localhost:8089/services/apps/local/$app" 2>/dev/null || echo 000)"
    info "$app : HTTP $code (200 = installed)"
done
if [ "$SKIP_BOTS" -ne 1 ]; then
    bots="$(docker exec "$CONTAINER" curl -ks -u "admin:$PASSWORD" \
        "https://localhost:8089/services/data/indexes/botsv1?output_mode=json" 2>/dev/null \
        | awk -F'[:,]' '/totalEventCount/ {gsub(/[^0-9]/,"",$2); print $2; exit}')"
    info "botsv1 index : ${bots:-not visible yet} events"
fi

cat <<EOF

===============================================================
 Splunk AITK + DSDL POC is up.
===============================================================
  Web UI   : http://localhost:8000
  Username : admin
  Password : $PASSWORD

The compose file also starts the golden container as `mltk-dry2`, so Docker
Desktop should show it under the same `splunkaitk` stack.

Next: open DSDL -> Configuration -> Setup and enter (Docker mode):
  Container Environment : Docker
  Docker Host           : tcp://docker-proxy:2375
  Endpoint URL          : host.docker.internal
  External URL          : localhost
  Check Hostname        : Disabled   (under Certificate Settings)
  (tick the risk checkbox, then click Test & Save)

Then DSDL -> Containers -> confirm the golden-image container is running and
open JupyterLab.

DGA detection POC walkthrough (botsv1 DNS): see dga/README.md
EOF
