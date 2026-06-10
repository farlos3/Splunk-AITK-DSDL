# Splunk AITK + DSDL — POC Lab

[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Splunk Docs](https://img.shields.io/badge/Splunk-Docs-FFB000?logo=splunk&logoColor=black)](https://docs.splunk.com/Documentation/Splunk)
[![DSDL](https://img.shields.io/badge/DSDL-5.2.x-000000)](https://splunkbase.splunk.com/app/4607)
[![AITK](https://img.shields.io/badge/AITK%2FMLTK-app%202890-0B7285)](https://splunkbase.splunk.com/app/2890)

Local Splunk Enterprise in Docker, pre-wired to run a proof-of-concept of
Splunk's machine-learning / AI stack:

- **AITK** — *Splunk AI Toolkit* (formerly **MLTK**, the Machine Learning
  Toolkit) — the in-Splunk ML commands, assistants, and UI.
- **DSDL** — *Splunk App for Data Science and Deep Learning* (formerly the
  Deep Learning Toolkit / DLTK). It **extends AITK** with prebuilt Docker
  containers (TensorFlow, PyTorch, NLP/LLM libraries) where your heavy
  model code actually runs.

The concrete POC wired up here: **DGA domain detection** — train a
character-level neural network in the DSDL container and score the DNS
queries in the **BOTSv1** dataset. Walkthrough in [`dga/README.md`](dga/README.md).

Same Docker-first philosophy as the sibling
[`Splunk-Environment-Lab`](../Splunk-Environment-Lab): one compose file,
one setup script (PowerShell **and** bash), named volumes for persistence,
a reset script, and a `.gitignore` that keeps the big/secret stuff out.

> 📖 **New here? Follow the step-by-step [Setup Guide → `docs/SETUP.md`](docs/SETUP.md)** —
> the full zero-to-working walkthrough with verification checks and
> troubleshooting. The sections below are the condensed reference.

## How the pieces fit

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Splunk container (splunk-aitk)                                             │
│   apps: Python-for-Scientific-Computing → AITK/MLTK → DSDL                 │
│   Web :8000   HEC :8088   Mgmt :8089   Fwd :9997                           │
│                                                                            │
│   `| fit MLTKContainer ...`  ──pushes data──▶  golden container :5000      │
│            ▲                                          │                     │
│            └────────────── results ──────────────────┘                     │
└───────────────┬───────────────────────────────────────────────────────────┘
                │ DSDL talks to the Docker daemon via the mounted socket
                │   /var/run/docker.sock   (Docker Host: unix://var/run/docker.sock)
                ▼
        Host Docker (Docker Desktop)  ── spins up sibling container ──▶
        golden image  splunk/mltk-container-golden-cpu
          :5000 model API   :8888 JupyterLab   :6006 TensorBoard
```

DSDL doesn't run your model *inside* Splunk — it asks the Docker daemon to
launch the **golden image** container, streams search results to its
`:5000` API, and gets predictions back. JupyterLab (`:8888`) is where you
develop the model code interactively. Because Splunk itself runs in a
container here, we mount the host's Docker socket so DSDL can spawn those
sibling containers on the host Docker.

## Prerequisites

- **Docker Desktop** running (Linux containers / WSL2 backend on Windows).
- **~35–40 GB free disk**: Splunk image (~2.5 GB) + DSDL golden image
  (a few GB) + the BOTSv1 download+extract under `bots-data/` (~15 GB) + the
  BOTSv1 volume (~9 GB).
- A free **Splunkbase** account to download the three apps (next section).
- The **BOTSv1 dataset**. This project is **self-contained**: the setup
  script keeps its own copy under `bots-data/botsv1/` and loads it into
  **this project's own** `splunkaitk_splunk-botsv1` volume. If that folder is
  empty it downloads the ~6 GB `.tgz` itself (resumable). It never reads from
  `Splunk-Environment-Lab`. Already have the `.tgz`? Drop it in
  `bots-data/botsv1/` and pass `-SkipDownload`.
- 8 GB+ RAM free is comfortable; the golden image is the hungry part.

## Step 1 — Stage the three apps (one time, manual)

The apps live on Splunkbase behind a login, so they can't be
auto-downloaded the way BOTS data was. Download these and drop the `.tgz`
into [`splunk-apps/`](splunk-apps/) — full instructions and direct links
are in [`splunk-apps/README.md`](splunk-apps/README.md):

1. **Python for Scientific Computing (PSC)** — *Linux 64-bit* — app 2882
2. **Splunk AI Toolkit / MLTK** — app 2890
3. **Splunk App for Data Science and Deep Learning (DSDL)** — app 4607

## Step 2 — Bring it up

```powershell
# Windows (PowerShell)
.\setup.ps1                 # stage apps first, then run this (downloads BOTSv1)
.\setup.ps1 -SkipPull       # don't pre-pull the golden image (DSDL pulls later)
.\setup.ps1 -SkipBots       # set up without loading BOTSv1
.\setup.ps1 -SkipDownload   # use a .tgz already in bots-data\botsv1\
.\setup.ps1 -Force          # force-recreate container + repopulate BOTSv1
```

```bash
# Linux / macOS / Git Bash / WSL
./setup.sh
./setup.sh --skip-pull
./setup.sh --skip-bots
./setup.sh --skip-download
./setup.sh --force
```

The script verifies Docker, finds your three `.tgz` files, writes
`docker/.env`, copies BOTSv1 into this project's own volume, pre-pulls the
golden image, starts Splunk, and waits for it to go healthy. **First boot
takes a few minutes** because Splunk installs the three apps before it
answers. The one-time BOTSv1 copy (~9 GB) also adds a few minutes.

When it finishes: <http://localhost:8000> — user `admin`, password from
`docker/.env` (default `p@ssw0rd`).

## Step 3 — Point DSDL at Docker (one time, in the UI)

In Splunk: open **Splunk App for Data Science and Deep Learning →
Configuration → Setup**, choose **Docker**, and enter:

| Field | Value |
|---|---|
| Container Environment | `Docker` |
| Docker Host | `tcp://docker-proxy:2375` |
| Endpoint URL | `host.docker.internal` |
| External URL | `localhost` |
| Check Hostname (Certificate Settings) | `Disabled` |

Tick **"I fully understand the potential data and security risks…"**, then
click **Test & Save**. Then go to **Containers**, start the **golden-image**
container, and open **JupyterLab** to confirm the round trip works.

> **Why `tcp://docker-proxy:2375` and not `unix://var/run/docker.sock`?**
> Splunk runs in a container as uid 41812 and can't read the root-owned
> Docker socket (DSDL Test & Save fails with `Permission denied`). The
> compose file runs a `docker-proxy` sidecar (tecnativa/docker-socket-proxy)
> that holds the socket and exposes a scoped Docker API over TCP, which the
> splunk container reaches by name. `Endpoint URL = host.docker.internal`
> because the model containers DSDL spawns publish their ports on the host,
> and from inside the splunk container `localhost` is itself, not the host.

## Step 4 — Run the DGA detection POC

Full walkthrough in [`dga/README.md`](dga/README.md): load the model
notebook into the container, train on the labeled domain set, then score
BOTSv1's DNS queries. The short version once the container is running:

```spl
# train (after loading the dga_neural_network notebook + the lookup)
| inputlookup dga_training_domains.csv
| fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model

# score botsv1 DNS and surface the most DGA-looking domains
index=botsv1 sourcetype=stream:dns message_type=Query
| eval domain=lower(mvindex('query{}',0))
| stats count by domain
| apply dga_model
| where is_dga_predicted=1 | sort - dga_score | table domain count dga_score
```

## Resetting

Splunk Enterprise's free trial lasts 60 days from first boot, then drops to
Splunk Free. To start clean (and re-install the apps from `splunk-apps/`):

```powershell
.\docker\reset.ps1               # wipe container + state, KEEP BOTSv1 volume
.\docker\reset.ps1 -Full         # also wipe BOTSv1 (next setup re-copies ~9 GB)
.\docker\reset.ps1 -Containers   # also remove leftover DSDL model containers
```

```bash
./docker/reset.sh
./docker/reset.sh --full
./docker/reset.sh --containers
```

Reset wipes `splunk-etc` (installed apps + DSDL config) and `splunk-var`
(trial state, _internal logs) but **keeps** the `splunkaitk_splunk-botsv1`
volume by default, so botsv1 is available immediately after reboot with no
re-copy. It does **not** delete the golden image either, so the next boot is
only slowed by re-installing the three apps. Note: because botsv1 lives in
its own volume mounted under `etc/apps`, the dataset survives a normal reset
even though `splunk-etc` is wiped.

## Folder layout

```
Splunk-AITK-DSDL/
├── setup.ps1 / setup.sh        ← apps + BOTSv1 volume + golden image + up + wait healthy
├── docker/
│   ├── docker-compose.yml      ← splunk service + docker.sock + named volumes/network
│   ├── .env.example            ← template for the generated docker/.env
│   └── reset.ps1 / reset.sh     ← nuke container + state; -Full also wipes BOTSv1
├── docs/
│   └── SETUP.md                ← full step-by-step setup guide (start here)
├── splunk-apps/                ← stage Splunkbase .tgz here (gitignored payloads)
│   └── README.md               ← which apps to download + direct links
├── bots-data/botsv1/           ← BOTSv1 staging (download + extract live here)
├── dga/                        ← the DGA detection POC
│   ├── dga_neural_network.ipynb   ← DSDL model notebook (char-level CNN)
│   ├── dga_training_domains.csv   ← labeled legit-vs-DGA training set
│   ├── make_training_data.py      ← regenerates the CSV
│   └── README.md                  ← full train + score walkthrough
├── .gitignore
└── README.md
```

## Ports

| Port | Service | Notes |
|---|---|---|
| 8000 | Splunk Web | http://localhost:8000 |
| 8088 | HTTP Event Collector | token in `docker/.env` |
| 8089 | Splunk REST / Mgmt | DSDL model container calls back here |
| 9997 | Forwarder receiver | for a future Universal Forwarder |
| 5000 | DSDL model API | on the golden container (DSDL-published) |
| 8888 | JupyterLab | on the golden container (DSDL-published) |
| 6006 | TensorBoard | on the golden container (DSDL-published) |

## Troubleshooting

- **DSDL "Test & Save" fails with `Permission denied`** — already handled:
  the compose file routes DSDL through the `docker-proxy` sidecar instead of
  mounting the socket into Splunk. Make sure you used Docker Host
  `tcp://docker-proxy:2375` (not `unix://...`) and that `dsdl-docker-proxy`
  is running (`docker ps`). If it isn't, `docker compose -f
  docker/docker-compose.yml up -d`.
- **`host.docker.internal` not resolving / container start times out** — on
  Docker Desktop it's automatic; on plain Linux Docker add
  `extra_hosts: ["host.docker.internal:host-gateway"]` to the splunk service.
- **App install didn't happen** — check the boot log:
  `docker logs -f splunk-aitk` and look for the ansible "install_apps"
  play. Make sure all three `.tgz` are in `splunk-apps/` and you picked the
  **Linux** PSC build. Re-run `reset.ps1` to retry a clean install.
- **Golden image pull is slow / fails** — re-run with `-SkipPull` and let
  DSDL pull it on first container start, or
  `docker pull splunk/mltk-container-golden-cpu:5.2.3` manually.
- **Spawned model container can't talk to Splunk** — both must share the
  `splunk-dsdl` network. If your DSDL version exposes a container-network
  field on the Setup page, set it to `splunk-dsdl`.

## References

- [DSDL overview & architecture](https://docs.splunk.com/Documentation/DSDL/latest/User/IntroDSDL)
- [Configure DSDL (Docker / K8s / OpenShift)](https://docs.splunk.com/Documentation/DSDL/latest/User/ConfigDSDL)
- [splunk/splunk-mltk-container-docker (golden images)](https://github.com/splunk/splunk-mltk-container-docker)
- [Splunk AI Toolkit / MLTK on Splunkbase](https://splunkbase.splunk.com/app/2890)
