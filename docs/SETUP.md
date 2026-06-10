# Setup Guide — Splunk AITK + DSDL POC

End-to-end install, from zero to a working DGA-detection demo on BOTSv1.
Follow the steps in order; each one tells you what success looks like before
you move on.

- **Time:** ~30–60 min, mostly downloads (Splunk image, golden image, BOTSv1).
- **Audience:** running this locally on **Windows + Docker Desktop**. The
  bash equivalents (`setup.sh`, `reset.sh`) work the same on macOS/Linux/WSL.

---

## 0. What you'll end up with

```
Docker Desktop (host)
├── splunk-aitk           Splunk Enterprise + AITK + PSC + DSDL   (web :8000)
├── dsdl-docker-proxy     scoped Docker API for DSDL              (tcp :2375, internal)
└── mltk-container-*      DSDL "golden image" model container     (:5000 / :8888 / :6006)
                          ^ created by DSDL on demand, not by compose

Volumes:  splunkaitk_splunk-etc · splunkaitk_splunk-var · splunkaitk_splunk-botsv1
Network:  splunk-dsdl
```

| Port | Service | Used for |
|---|---|---|
| 8000 | Splunk Web | the UI |
| 8088 | HEC | optional: push results from the model container back to Splunk |
| 8089 | Splunk mgmt/REST | optional: model container pulls data from Splunk |
| 5000 | DSDL model API | `fit/apply MLTKContainer` traffic (on the golden container) |
| 8888 | JupyterLab | develop the model notebook (on the golden container) |
| 6006 | TensorBoard | optional training visualisation |

---

## 1. Prerequisites

- **Docker Desktop** running, Linux-containers / WSL2 backend.
- **~35–40 GB free disk** (Splunk image + golden image + BOTSv1 download &
  extract + volumes).
- **8 GB+ free RAM** while the golden container runs.
- A free **Splunkbase** account: <https://splunkbase.splunk.com> (needed to
  download the three apps — they are not auto-downloadable).

Verify Docker is alive:

```powershell
docker info        # should print server details, not an error
```

---

## 2. Stage the three Splunk apps (manual, one time)

Download these from Splunkbase and drop the files into **`splunk-apps/`**.
Splunkbase serves them as `.tgz` **or** `.spl` — both work (same format).

| # | App | Splunkbase | Pick |
|---|-----|-----------|------|
| 1 | **Python for Scientific Computing (PSC)** | [app/2882](https://splunkbase.splunk.com/app/2882) | **Linux 64-bit** build (the container is Linux — *not* the Windows build) |
| 2 | **Splunk AI Toolkit (AITK)** *(was MLTK)* | [app/2890](https://splunkbase.splunk.com/app/2890) | latest for your Splunk version |
| 3 | **Splunk App for Data Science & Deep Learning (DSDL)** | [app/4607](https://splunkbase.splunk.com/app/4607) | latest |

After downloading, `splunk-apps/` should look roughly like:

```
splunk-apps/
├── python-for-scientific-computing-for-linux-64-bit_432.tgz
├── splunk-ai-toolkit_574.tgz
└── splunk-app-for-data-science-and-deep-learning_524.spl
```

> Install order **PSC → AITK → DSDL** is enforced by the setup script — you
> don't have to rename or reorder anything. If a file isn't matched, make
> sure its name contains `scientific-computing`+`linux`, `ai-toolkit` (or
> `machine-learning-toolkit`), or `deep-learning` respectively.

---

## 3. Run the setup script

From the repo root:

```powershell
.\setup.ps1
```

```bash
./setup.sh
```

What it does, in order:

1. **Pre-flight** — checks Docker is reachable.
2. **Find the 3 apps** in `splunk-apps/` and write `docker/.env` with
   `SPLUNK_APPS_URL` (so Splunk installs them at first boot).
3. **Pull the DSDL golden image** (`splunk/mltk-container-golden-cpu`, a few GB).
4. **Populate BOTSv1** into this project's own `splunkaitk_splunk-botsv1`
   volume — downloads the ~6 GB archive into `bots-data/botsv1/` if it isn't
   there already (self-contained; never reads from `Splunk-Environment-Lab`).
5. **`docker compose up -d`** and wait for Splunk to report healthy. The same
  compose run also starts the golden container as `mltk-dev` (DEV mode, so it
  runs JupyterLab), grouped under the `splunkaitk` stack in Docker Desktop.
6. Print the values to enter on the DSDL Setup page (step 5 below).

Useful flags (same idea for `--flag` in bash):

| Flag | Effect |
|---|---|
| `-SkipPull` | don't pre-pull the golden image (DSDL pulls it later) |
| `-SkipBots` | set up without loading BOTSv1 |
| `-SkipDownload` | use a `.tgz` already sitting in `bots-data\botsv1\` |
| `-Force` | recreate the container and repopulate BOTSv1 |

**Tip for a fast first check:** `.\setup.ps1 -SkipPull -SkipBots` brings up
just Splunk + the 3 apps in ~5–8 min so you can confirm they install, then
run the full `.\setup.ps1` later for the golden image + data.

**Success looks like:** the script ends with "Splunk AITK + DSDL POC is up"
and <http://localhost:8000> loads (login `admin` / your password from
`docker/.env`, default `p@ssw0rd`). You should also see `mltk-dev` running
under the same compose stack (JupyterLab at `https://localhost:8888`).

Confirm the containers and data:

```powershell
docker ps --filter name=splunk-aitk --filter name=dsdl-docker-proxy
# in Splunk search:  index=botsv1 earliest=0 | stats count   -> millions of events
```

---

## 4. Confirm the apps loaded

In Splunk open **Splunk App for Data Science and Deep Learning →
Configuration → Setup**. The top of the page should show **"2 dependencies
found"**:

- AI Toolkit — version 5.x
- Python for Scientific Computing — version 4.x

If it says a dependency is missing, the app didn't install — see
[Troubleshooting](#troubleshooting).

---

## 5. Configure DSDL → Docker (one time)

On that same Setup page, choose **Docker** and enter exactly:

| Field | Value |
|---|---|
| Container Environment | `Docker` |
| **Docker Host** | `tcp://docker-proxy:2375` |
| **Endpoint URL** | `host.docker.internal` |
| **External URL** | `localhost` |
| Docker network | *(leave empty)* |
| **Check Hostname** *(Certificate Settings)* | `Disabled` |

Leave Kubernetes, Observability, Splunk Access, and Splunk HEC at their
defaults (`No`/empty) for the POC. Tick **"I fully understand the potential
data and security risks…"** and click **Test & Save**.

> For a **field-by-field reference of every option on this page** (including
> the optional Splunk Access / HEC sections), see
> [`DSDL-SETTINGS.md`](DSDL-SETTINGS.md).

**Why these values** (this is the non-obvious part):

- Splunk runs *inside* a container as uid 41812 and **cannot read the
  root-owned `/var/run/docker.sock`** — pointing DSDL at
  `unix://var/run/docker.sock` fails with `Permission denied`. The compose
  file therefore runs a **`docker-proxy`** sidecar
  (tecnativa/docker-socket-proxy) that holds the socket and exposes a scoped
  Docker API on `tcp://docker-proxy:2375`, which the splunk container reaches
  by name. → **Docker Host = `tcp://docker-proxy:2375`**.
- The model containers DSDL spawns run on the **host** Docker and publish
  their ports there. From inside the splunk container, `localhost` is the
  splunk container itself — to reach the host you need
  `host.docker.internal`. → **Endpoint URL = `host.docker.internal`**.
- Your browser runs on the host, so JupyterLab is at `localhost:8888`. →
  **External URL = `localhost`**.
- The prebuilt containers use a self-signed dev cert whose hostname won't
  match, so **Check Hostname = Disabled** (else Test & Save fails on cert
  validation).

**Success looks like:** a green "Setup successful" / saved message.

---

## 6. Open the model container / JupyterLab

The golden image runs as the **compose service `mltk-dev`** in DEV mode — it
starts with the stack, so you do **not** start one from the DSDL Containers
page (that would collide on ports 5000/8888).

1. Confirm it's up: `docker ps` shows `mltk-dev` with
   `0.0.0.0:8888->8888` and `0.0.0.0:5000->5000`.
2. Open **`https://localhost:8888`** — **HTTPS, not http** (it serves a
   self-signed cert; click through the browser warning). Plain
   `http://localhost:8888` returns *"didn't send any data"*.
3. Log in with password **`splunkdsdl`** (set via `JUPYTER_PASSWD` in the
   compose file).

**Success looks like:** `docker ps` shows `mltk-dev` under the `splunkaitk`
stack, and `https://localhost:8888` loads the JupyterLab login.

> `fit/apply MLTKContainer` reaches this same container's `:5000` API via the
> Endpoint URL (`host.docker.internal`) you saved in step 5 — one container
> serves both Jupyter and the model API.

> How to actually work in JupyterLab (the notebook→algorithm model, the
> dev loop, loading the DGA notebook): [`JUPYTER.md`](JUPYTER.md).

---

## 7. Run the DGA detection POC

The model + data are ready. Full walkthrough:
[`dga/README.md`](../dga/README.md). Short version once the golden container
is running:

```spl
# train (after loading the dga_neural_network notebook + the lookup)
| inputlookup dga_training_domains.csv
| fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model

# score botsv1 DNS, surface the most DGA-looking domains
index=botsv1 sourcetype=stream:dns message_type=Query
| eval domain=lower(mvindex('query{}',0))
| stats count by domain
| apply dga_model
| where is_dga_predicted=1 | sort - dga_score | table domain count dga_score
```

---

## Day-2: reset & teardown

```powershell
# fast reset: wipe container + state, KEEP BOTSv1 (re-installs apps on boot)
.\docker\reset.ps1
# also wipe BOTSv1 (next setup re-copies ~9 GB)
.\docker\reset.ps1 -Full
# also remove leftover DSDL model containers
.\docker\reset.ps1 -Containers
```

```bash
./docker/reset.sh            # fast
./docker/reset.sh --full
./docker/reset.sh --containers
```

Stop everything without deleting data:

```powershell
docker compose -f docker\docker-compose.yml stop
```

Nuke absolutely everything including all volumes:

```powershell
docker compose -f docker\docker-compose.yml down -v
```

---

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| `Could not find the … package (.tgz/.spl) in splunk-apps/` | An app is missing or named oddly. Check all three are in `splunk-apps/` and the names contain the expected keywords (see step 2). PSC must be the **Linux** build. |
| DSDL Setup: `Permission denied` on Docker API | You used `unix://var/run/docker.sock`. Use **`tcp://docker-proxy:2375`** and confirm `dsdl-docker-proxy` is running (`docker ps`). If absent: `docker compose -f docker/docker-compose.yml up -d`. |
| Changed the compose file but nothing changed | Don't use `docker compose restart` (keeps old config). Use **`docker compose ... up -d`** — it recreates only what changed. |
| DSDL "2 dependencies found" missing one | App didn't install. `docker logs -f splunk-aitk` and look for the ansible `install_apps` play. Re-run `reset.ps1` for a clean install. Verify PSC is the **Linux** build. |
| Test & Save fails on certificate / hostname | Set **Check Hostname = Disabled** under Certificate Settings. |
| Container start times out / can't reach `host.docker.internal` | Docker Desktop provides it automatically; on plain Linux Docker add `extra_hosts: ["host.docker.internal:host-gateway"]` to the `splunk` service. |
| Golden image pull is slow or fails | Re-run setup with `-SkipPull` and let DSDL pull it, or `docker pull splunk/mltk-container-golden-cpu:5.2.3` manually. |
| `botsv1` index empty | Give Splunk a minute after boot, re-check. If still empty, `reset.ps1 -Full` then `setup.ps1` to repopulate the volume. |

---

## Notes for graders / reviewers

- The three Splunkbase apps are **not** committed (license + size) — they're
  gitignored and staged manually in `splunk-apps/`.
- BOTSv1 and `docker/.env` are also gitignored. Everything needed to rebuild
  is in `setup.*` + `docker/docker-compose.yml`.
- Windows PowerShell 5.1 note: the `.ps1` scripts are ASCII-only with a BOM;
  PS 5.1 mis-parses non-ASCII in BOM-less files.
