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
queries in the **BOTSv1** dataset.

>  **Start here → [`docs/GUIDE.md`](docs/GUIDE.md)** — one follow-along
> handbook covering everything in order:
> [1 Set up](docs/GUIDE.md#1-set-up-the-lab) ·
> [2 Configure DSDL](docs/GUIDE.md#2-configure-the-dsdl-setup-page) ·
> [3 JupyterLab](docs/GUIDE.md#3-develop-models-in-jupyterlab) ·
> [4 HEC](docs/GUIDE.md#4-get-data-in-with-hec). This README is just the
> overview + repo map.

## How the pieces fit

```
┌───────────────────────────────────────────────────────────────────────────┐
│ Splunk container (splunk-aitk)                                            │
│   apps: Python-for-Scientific-Computing → AITK/MLTK → DSDL                │
│   Web :8000   HEC :8088   Mgmt :8089   Fwd :9997                          │
│                                                                           │
│   `| fit MLTKContainer ...`  ── pushes data ──▶  mltk-dev :5000 (HTTPS)     
│            ▲                                         │                    |
│            └────────────── results ──────────────────┘                    |
└───────────────┬───────────────────────────────────────────────────────────┘
                │ DSDL POSTs to Endpoint URL host.docker.internal:5000.
                │ Compose runs the golden container itself (no DSDL spawn).
                ▼
        Compose-managed model container `mltk-dev`  (MODE_DEV_PROD=DEV)
          image: splunk/mltk-container-golden-cpu
          :5000 model API (HTTPS)   :8888 JupyterLab (HTTPS)   :6006 TensorBoard
```

DSDL doesn't run your model *inside* Splunk — it streams search results to
the **golden image** container's `:5000` API and gets predictions back.
JupyterLab (`:8888`) is where you develop the model code interactively. This
lab runs the golden container as the compose service **`mltk-dev`** in DEV
mode (which is what starts JupyterLab) so it's always available and grouped
under the `splunkaitk` stack. The `docker-proxy` sidecar is only there so
DSDL's *Test & Save* can validate the Docker connection.
[More on the architecture → `docs/AI-Usage-Flow.pdf`](docs/AI-Usage-Flow.pdf).

## The AI pieces — build them, then break them

Beyond the DGA POC, this lab teaches three AI building blocks. They are **not**
peers — two combine into one capability, and the third is a lens laid over it:

| Piece | Stands alone? | Role |
|---|---|---|
| **Local LLM** (Ollama) | Yes — LLM Chat reasons over your search rows | the engine |
| **MCP** | **No** — a layer *on top of* the LLM that hands it Splunk as a tool | makes the LLM agentic |
| **MITRE ATLAS** | n/a — a framework, not a running service | the red-team lens |

The whole lab follows one arc — **BUILD → BREAK**:

- **BUILD** two capabilities: the DGA **classifier**
  ([`poc/dga/`](poc/dga/README.md)) and the **local LLM + MCP** assistant
  ([`poc/mcp/`](poc/mcp/README.md)). The LLM alone reads what you paste in; add
  **MCP** and it runs its own Splunk searches — the agentic "SOC assistant" that
  is the hero of the LLM track.
- **BREAK** both with **MITRE ATLAS** ([`atlas/`](atlas/README.md)) — one lens,
  two targets: the *classifier* (evade, poison) and the *LLM + MCP* assistant
  (prompt injection, **plugin compromise**, data leakage).

| Capability you BUILD | How | How ATLAS BREAKS it |
|---|---|---|
| DGA classifier | `fit` / `apply MLTKContainer` | Evade `AML.T0015`, Poison `AML.T0020` |
| Local LLM (Ollama) | LLM Chat over results | Prompt injection `AML.T0051`, Jailbreak `AML.T0054` |
| **LLM + MCP** (hero) | LLM calls Splunk as a tool | **Plugin compromise `AML.T0053`** — only reachable once MCP is connected |

Walkthroughs: build the LLM+MCP assistant in
[Guide 5](docs/GUIDE.md#5-llm-integrations-and-mcp); red-team both tracks in
[Guide 6](docs/GUIDE.md#6-red-team-with-mitre-atlas).

## Prerequisites

- **Docker Desktop** running (Linux containers / WSL2 backend on Windows).
- **~35–40 GB free disk** (Splunk image + DSDL golden image + BOTSv1 download
  & extract + volumes) and **8 GB+ free RAM** while the golden container runs.
- A free **Splunkbase** account to download the three apps.
- The **BOTSv1 dataset** is fetched for you: this project is self-contained —
  `setup.*` keeps its own copy under `bots-data/botsv1/` and loads it into
  this project's own `splunkaitk_splunk-botsv1` volume (downloads the ~6 GB
  `.tgz` if absent). It never reads from `Splunk-Environment-Lab`.

## Quick start

Full walkthrough with success-checks and troubleshooting is in
**[`docs/GUIDE.md`](docs/GUIDE.md)**. The gist:

1. **Stage the 3 Splunkbase apps** into [`splunk-apps/`](splunk-apps/) — PSC
   *Linux 64-bit* (app 2882) · AITK (app 2890) · DSDL (app 4607). Direct links
   in [`splunk-apps/README.md`](splunk-apps/README.md).
   → [Guide 1.3](docs/GUIDE.md#13-stage-the-three-splunk-apps)

2. **Bring it up** from the repo root — installs the apps, loads BOTSv1, and
   starts Splunk + the `mltk-dev` golden container:

   ```bash
   ./setup.sh         # first run; flags: --skip-pull --skip-bots --skip-download --force
   ```

   Then open <http://localhost:8000> — `admin` / password from `docker/.env`
   (default `p@ssw0rd`). → [Guide 1.4](docs/GUIDE.md#14-run-the-setup-script)

3. **Point DSDL at Docker** (Setup page → Docker): Docker Host
   `tcp://docker-proxy:2375`, Endpoint URL `host.docker.internal`, External
   URL `localhost`, Check Hostname `Disabled` → **Test & Save**.
   → [Guide 2](docs/GUIDE.md#2-configure-the-dsdl-setup-page)

4. **Develop & run** — open JupyterLab at **`https://localhost:8888`** (HTTPS;
   password `splunkdsdl`), then run the DGA POC.
   → [Guide 3](docs/GUIDE.md#3-develop-models-in-jupyterlab) ·
   [`poc/dga/README.md`](poc/dga/README.md)

   ```spl
   | inputlookup dga_training_domains.csv
   | fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model

   index=botsv1 sourcetype=stream:dns message_type=Query
   | eval domain=lower(mvindex('query{}',0))
   | stats count by domain | apply dga_model
   | where is_dga_predicted=1 | sort - dga_score | table domain count dga_score
   ```

> **Reset / teardown** (`./docker/reset.sh`, `--full`, `down -v`) and a full
> troubleshooting table live in
> [Guide 1.6–1.7](docs/GUIDE.md#16-reset--teardown).

## Documentation

| Doc | What's in it |
|---|---|
| **[`docs/GUIDE.md`](docs/GUIDE.md)** | The handbook — [setup](docs/GUIDE.md#1-set-up-the-lab) → [DSDL config](docs/GUIDE.md#2-configure-the-dsdl-setup-page) → [JupyterLab](docs/GUIDE.md#3-develop-models-in-jupyterlab) → [HEC](docs/GUIDE.md#4-get-data-in-with-hec) → [LLM + MCP](docs/GUIDE.md#5-llm-integrations-and-mcp) → [red-team with ATLAS](docs/GUIDE.md#6-red-team-with-mitre-atlas) |
| [`docs/AI-Usage-Flow.pdf`](docs/AI-Usage-Flow.pdf) | AITK vs DSDL concepts + the official architecture (printable) |
| [`poc/dga/README.md`](poc/dga/README.md) | **BUILD** — the DGA classifier: train + score walkthrough |
| [`poc/mcp/README.md`](poc/mcp/README.md) | **BUILD** — the local LLM + MCP assistant: LLM Chat over BOTSv1, then MCP tool-use |
| [`atlas/README.md`](atlas/README.md) | **BREAK** — **MITRE ATLAS** as the red-team lens over *both* targets: the classifier (evade + poison) and the LLM + MCP assistant ([Guide 6](docs/GUIDE.md#6-red-team-with-mitre-atlas)) |
| [`splunk-apps/README.md`](splunk-apps/README.md) | Which Splunkbase apps to download + links |
| [`bots-data/README.md`](bots-data/README.md) | BOTSv1 staging + how it's loaded |

## Ports

| Port | Service | Notes |
|---|---|---|
| 8000 | Splunk Web | http://localhost:8000 |
| 8088 | HTTP Event Collector | HTTPS; token in `docker/.env` ([Guide 4](docs/GUIDE.md#4-get-data-in-with-hec)) |
| 8089 | Splunk REST / Mgmt | DSDL model container calls back here |
| 9997 | Forwarder receiver | for a future Universal Forwarder |
| 5000 | DSDL model API | on the golden container (`mltk-dev`) |
| 8888 | JupyterLab | on the golden container (HTTPS) |
| 6006 | TensorBoard | on the golden container |

## Folder layout

```
Splunk-AITK-DSDL/
├── setup.sh                    ← apps + BOTSv1 volume + golden image + up + wait healthy
├── docker/
│   ├── docker-compose.yml      ← splunk + docker-proxy + mltk-dev; named volumes/network
│   ├── .env.example            ← template for the generated docker/.env
│   └── reset.sh                ← nuke container + state; --full also wipes BOTSv1
├── docs/
│   ├── GUIDE.md                ← one handbook: setup → DSDL → JupyterLab → HEC (start here)
│   └── AI-Usage-Flow.pdf       ← AITK vs DSDL flow + architecture explainer (printable)
├── splunk-apps/                ← stage Splunkbase .tgz here (gitignored payloads)
│   └── README.md               ← which apps to download + direct links
├── bots-data/botsv1/           ← BOTSv1 staging (download + extract live here)
├── poc/                         ← BUILD: the two AI capabilities
│   ├── dga/                        ← the DGA classifier POC
│   │   ├── dga_neural_network.ipynb   ← DSDL model notebook (char-level CNN)
│   │   ├── dga_training_domains.csv   ← labeled legit-vs-DGA training set
│   │   ├── make_training_data.py      ← regenerates the CSV
│   │   └── README.md                  ← full train + score walkthrough
│   └── mcp/                        ← the local LLM + MCP assistant
│       ├── setup_llm.sh               ← start Ollama, pull the model, smoke-test
│       └── README.md                  ← LLM Chat over BOTSv1 + MCP walkthrough
├── atlas/                       ← BREAK: MITRE ATLAS red-team (classifier + LLM/MCP)
│   ├── craft_adversarial_domains.py  ← evasion: DGA domains shaped to look benign
│   ├── poison_training_data.py       ← poisoning: mislabel DGA in the training set
│   ├── CASE-STUDIES.md               ← real ATLAS incidents (AML.CS00xx) behind the attacks
│   └── README.md                     ← evasion + poisoning + LLM/MCP red-team + defenses
├── .gitignore
└── README.md
```

## References

- [DSDL overview & architecture](https://docs.splunk.com/Documentation/DSDL/latest/User/IntroDSDL)
- [Configure DSDL (Docker / K8s / OpenShift)](https://docs.splunk.com/Documentation/DSDL/latest/User/ConfigDSDL)
- [splunk/splunk-mltk-container-docker (golden images)](https://github.com/splunk/splunk-mltk-container-docker)
- [Splunk AI Toolkit / MLTK on Splunkbase](https://splunkbase.splunk.com/app/2890)
- [Get data with HTTP Event Collector (Splunk docs)](https://help.splunk.com/en/splunk-enterprise/get-started/get-data-in/10.4/get-data-with-http-event-collector)
- [MITRE ATLAS — adversarial ML threat matrix](https://atlas.mitre.org/) ([the matrix](https://atlas.mitre.org/matrices/ATLAS))

---

<sub>All documentation in this repo — every `.md` file and [`docs/AI-Usage-Flow.pdf`](docs/AI-Usage-Flow.pdf) — was written with **Claude** (Anthropic's AI assistant).</sub>
