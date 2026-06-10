# DSDL Setup Page — Settings Reference

A field-by-field reference for the **Splunk App for Data Science and Deep
Learning → Configuration → Setup** page, tuned for **this POC** (Splunk in
Docker + the `docker-proxy` sidecar on Docker Desktop). For each field:
the value to enter here, what it does, and why.

> Install & first-run steps live in [`SETUP.md`](SETUP.md). This doc is only
> about what to type on the Setup page.

---

## TL;DR — minimum working config

Fill in just these; leave everything else at its default. Tick the risk
checkbox at the bottom and click **Test & Save**.

| Section | Field | Value |
|---|---|---|
| Docker | Docker Host | `tcp://docker-proxy:2375` |
| Docker | Endpoint URL | `host.docker.internal` |
| Docker | External URL | `localhost` |
| Certificate | Check Hostname | `Disabled` |
| Password | Jupyter Password | *(set your own, e.g. `dsdl-jupyter`)* |

Everything below explains each field and the optional sections you can turn
on later (Splunk Access / HEC for interactive notebooks).

---

## 1. Machine Learning Toolkit Installation  *(read-only check)*

Not editable — it just verifies the two prerequisites are installed. You
want to see **"2 dependencies found"**:

- **AI Toolkit** (AITK / MLTK) — 5.x
- **Python for Scientific Computing** — 4.x

If one is missing, the app won't work; fix the install before continuing
(see [SETUP.md → Troubleshooting](SETUP.md#troubleshooting)). Also set the
AI Toolkit app to **global permissions** so its knowledge objects are shared
(Apps → Manage Apps → AI Toolkit → Permissions → "All apps").

---

## 2. Container Environment Setup

Choose **Docker** (the left column). Leave the entire **Kubernetes** column
empty — it's for K8s/OpenShift clusters, not this lab.

### Docker Settings

| Field | Value here | What it is / why |
|---|---|---|
| **Docker Host** | `tcp://docker-proxy:2375` | How DSDL reaches a Docker daemon to create model containers. We use the `docker-proxy` sidecar instead of `unix://var/run/docker.sock` because the splunk process (uid 41812) can't read the root-owned socket → `Permission denied`. The proxy holds the socket and exposes a scoped TCP API the splunk container reaches by name. |
| **Endpoint URL** | `host.docker.internal` | Hostname Splunk uses to call the model container's API (`:5000`). The container runs on the **host** Docker and publishes its ports there; from inside the splunk container `localhost` is itself, so you must use `host.docker.internal` to hop to the host. **Hostname only** — no `https://`, no port (DSDL adds them). |
| **External URL** | `localhost` | Hostname put into the **JupyterLab / TensorBoard links** you click in the browser. Your browser is on the host, where the container's `:8888`/`:6006` are published → `localhost`. |
| **Docker network** | *(empty)* | Only needed for the LLM-RAG integration (Ollama / Milvus started via compose) — then set it to that compose network. Leave empty for the DGA POC. |
| **API Workers** | *(empty = 1)* | FastAPI worker threads inside the model container. 1 is fine for a POC; raise it only for heavy concurrent scoring. |
| **Splunk Docker Logging Endpoint** | *(empty)* | Optional: ships the container's stdout/stderr to Splunk via HEC. Not needed; you can read logs with `docker logs <mltk-container-…>`. |
| **Splunk Docker Logging (HEC) Token** | *(empty)* | Token for the logging endpoint above. Leave empty. |

> **Reference table on the page** lists deployment presets (linux /
> windows / docker / side-by-side). None match "Splunk-in-a-container talking
> to host Docker via a proxy", which is why our values are a hybrid:
> proxy host + `host.docker.internal` endpoint.

---

## 3. Certificate Settings

DSDL talks to the model container over **HTTPS only** (no plain HTTP option).
The prebuilt containers ship a self-signed dev certificate.

| Field | Value here | What it is / why |
|---|---|---|
| **Check Hostname** | `Disabled` | With a self-signed dev cert, the cert's hostname won't match `host.docker.internal`, so leaving this **Enabled** makes Test & Save fail on cert validation. Disable for the dev/POC setup. (Enable it only with your own properly-issued certs.) |
| **Certificate filename or path** | *(empty)* | Point DSDL at your own cert/CA chain on the Splunk instance instead of fetching the container's. Empty = use the container's self-signed cert. |
| **Enable container certificates** | `Yes` | Keep the container's built-in HTTPS cert. Set to `No` only if HTTPS is terminated upstream (e.g. a Kubernetes ingress), which doesn't apply here. |

---

## 4. Password Settings

| Field | Value here | What it is / why |
|---|---|---|
| **Endpoint Token** | *(empty = random)* | Bearer token protecting the container's `:5000` API. Empty → DSDL generates a random one (fine). Set a fixed value only if you script direct API calls. Takes effect on **newly started** containers. |
| **Jupyter Password** | *(set your own)* | Login password for JupyterLab. **Recommended to set** (e.g. `dsdl-jupyter`) so you know it; otherwise click "show the default Jupyter Lab password" to read the default. Takes effect on **newly started** containers. |

> Any change in this section only applies to **containers started after** the
> change — restart the model container if you edit it.

---

## 5. Observability Settings  *(optional — skip for POC)*

| Field | Value here | Note |
|---|---|---|
| **Enable Observability** | `No` | Sends container API traces to Splunk Observability Cloud. Needs a separate Observability account. Off for the lab. |
| Access Token / OTel Endpoint / Servicename | *(empty)* | Only used when Observability is `Yes`. |

---

## 6. Splunk Access Settings  *(optional — enable for interactive notebooks)*

Lets the model container **pull data from Splunk** using the Python SDK
(e.g. the interactive search bar in the `barebone_template` notebook). The
DGA POC's `fit/apply MLTKContainer` flow does **not** need this — turn it on
only if you want to query Splunk from inside JupyterLab.

| Field | Value here | What it is / why |
|---|---|---|
| **Enable Splunk Access** | `Yes` *(if you want it)* | Default `No`. |
| **Splunk Access Token** | *(a Splunk auth token)* | Create in Splunk **Settings → Tokens** (enable token auth first). Scope it to the minimum needed (e.g. read on `botsv1`). |
| **Splunk Host Address** | `host.docker.internal` | The model container reaches Splunk's mgmt port on the host-published `:8089`; from a sibling container that's `host.docker.internal`. |
| **Splunk Management Port** | `8089` | Splunk's REST/mgmt port (published by compose). |

> Takes effect on **newly started** containers — restart the model container
> after enabling.

---

## 7. Splunk HEC Settings  *(optional — enable to push results back)*

Lets the container **send data back into Splunk** (model output as indexed
events) via the HTTP Event Collector. Optional for the DGA POC.

| Field | Value here | What it is / why |
|---|---|---|
| **Enable Splunk HEC** | `Yes` *(if you want it)* | Default `No`. |
| **Splunk HEC Token** | *(your HEC token)* | The compose file sets `SPLUNK_HEC_TOKEN` (default `aitk-hec-token-CHANGE-ME`, see `docker/.env`). Use that, or create a fresh token under **Settings → Data inputs → HTTP Event Collector** and make sure HEC is enabled (Global Settings → All Tokens = Enabled). |
| **Splunk HEC Endpoint URL** | `https://host.docker.internal:8088` | The container posts events to Splunk's HEC on the host-published `:8088`, over HTTPS. |

> Takes effect on **newly started** containers — restart after enabling.

---

## 8. Test & Save

1. Scroll to the top banner and tick
   **"I fully understand the potential data and security risks from the setup
   description above and proceed with the setup process on my own risk"**.
2. Click **Test & Save** (bottom of the page).
3. Green / "successful" = saved. Red = check the message against
   [SETUP.md → Troubleshooting](SETUP.md#troubleshooting) (most common:
   wrong Docker Host, or Check Hostname still Enabled).

After a successful save, go to **Containers**, start the **golden-cpu**
image, and open **JupyterLab**.

---

## Quick "what changes need a container restart?"

| Changed setting | Restart model container? |
|---|---|
| Docker Host / Endpoint / External URL | No — applies on next container create |
| Check Hostname / certs | No |
| Endpoint Token / Jupyter Password | **Yes** (newly started containers only) |
| Splunk Access / Splunk HEC | **Yes** (newly started containers only) |

To restart a running model container, stop & start it from DSDL → Containers
(don't `docker restart` it — DSDL needs to recreate it with the new env).
