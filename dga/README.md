# DGA detection POC — AITK + DSDL on BOTSv1 DNS

End-to-end proof of concept: train a character-level neural network inside
the DSDL golden container to tell **DGA** (algorithmically generated malware
domains) apart from **benign** domains, then score the DNS queries in the
**botsv1** dataset.

```
labeled domains (lookup)                 botsv1 DNS queries
        │                                        │
        │  | fit MLTKContainer ...               │  | apply dga_model
        ▼                                        ▼
   ┌──────────────────── DSDL golden container ────────────────────┐
   │  dga_neural_network.py  (char-CNN, Keras/TensorFlow)          │
   │  init → fit → save                     load → apply           │
   └───────────────────────────────────────────────────────────────┘
```

Files here:

| File | What it is |
|---|---|
| `dga_neural_network.ipynb` | The DSDL model notebook (the `# mltkc_*` cells DSDL compiles into a model). |
| `dga_training_domains.csv` | ~315 labeled rows (`domain,is_dga`) — balanced legit vs DGA. |
| `make_training_data.py` | Regenerates the CSV deterministically (`python make_training_data.py`). |

> The CSV is a small teaching set — enough to clearly separate random DGA
> strings from real domains, **not** a production model.

---

## Prereqs

1. The lab is up and healthy (`..\setup.ps1` finished), and botsv1 shows
   events: in Splunk run `index=botsv1 earliest=0 | stats count` — expect
   millions.
2. DSDL Setup page is configured (Docker mode) and you've started the
   **golden-image** container from **DSDL → Containers**.

## Step 1 — Load the model notebook into the container

Open **JupyterLab** at **`https://localhost:8888`** (HTTPS — password
`splunkdsdl`; it's the compose-managed `mltk-dev` container, see
[`../docs/JUPYTER.md`](../docs/JUPYTER.md)). Saving a notebook named
`<algo>.ipynb` auto-converts its tagged cells into `/srv/app/model/<algo>.py`,
which is what `algo=<algo>` then calls.

Easiest path that works on every DSDL build:

1. In the DSDL app, use **Build → "Create new notebook from barebone
   template"** and name it **`dga_neural_network`** (this creates both the
   `.ipynb` and the linked `.py` plumbing).
2. Open it in JupyterLab and replace each `# mltkc_import / _init / _fit /
   _apply / _save / _load / _summary` cell with the matching cell from
   [`dga_neural_network.ipynb`](dga_neural_network.ipynb) in this folder.
3. **Run all cells**, then **Save** — DSDL writes
   `/srv/app/model/dga_neural_network.py`.

(If your build doesn't have the template helper, upload
`dga_neural_network.ipynb` into `/srv/notebooks/` and use DSDL's
notebook→python conversion; the cell tags are already correct.)

> New to the JupyterLab side of DSDL — the notebook→algorithm mapping, the
> `# mltkc_*` cell contract, and the stage/iterate/fit dev loop? See
> [`../docs/JUPYTER.md`](../docs/JUPYTER.md).

## Step 2 — Make the labeled training set a lookup

Quick way — copy the CSV straight into the search app's lookups (run from
the repo root):

```powershell
docker exec splunk-aitk mkdir -p /opt/splunk/etc/apps/search/lookups
docker cp dga\dga_training_domains.csv splunk-aitk:/opt/splunk/etc/apps/search/lookups/dga_training_domains.csv
docker exec splunk-aitk chown splunk:splunk /opt/splunk/etc/apps/search/lookups/dga_training_domains.csv
```

```bash
docker exec splunk-aitk mkdir -p /opt/splunk/etc/apps/search/lookups
docker cp dga/dga_training_domains.csv splunk-aitk:/opt/splunk/etc/apps/search/lookups/dga_training_domains.csv
docker exec splunk-aitk chown splunk:splunk /opt/splunk/etc/apps/search/lookups/dga_training_domains.csv
```

(Or in the UI: **Settings → Lookups → Lookup table files → Add new**, upload
the CSV, destination app `search`.) Verify in a search:

```spl
| inputlookup dga_training_domains.csv | stats count by is_dga
```

## Step 3 — Train the model (fit)

```spl
| inputlookup dga_training_domains.csv
| fit MLTKContainer algo=dga_neural_network epochs=25
    is_dga from domain into app:dga_model
```

This streams the labeled rows to the container, runs `init → fit → save`,
and stores the model as `dga_model`. You'll get back the per-row training
output; the loss/accuracy are in the container logs (DSDL → Containers →
Logs, or `docker logs <mltk-container-...>`).

Smoke-test the trained model on a few obvious cases:

```spl
| makeresults
| eval domain="google.com" | append [| makeresults | eval domain="kq3v9zlxqpwmrt.top"]
| apply dga_model
| table domain dga_score is_dga_predicted
```

`google.com` should score near 0; the random string near 1.

## Step 4 — Score botsv1 DNS queries (apply)

```spl
index=botsv1 sourcetype=stream:dns message_type=Query
| eval domain=lower(mvindex('query{}',0))
| where isnotnull(domain) AND domain!=""
| rex field=domain "(?<reg_domain>[a-z0-9-]+\.[a-z0-9-]+)$"
| stats count by reg_domain
| rename reg_domain as domain
| apply dga_model
| where is_dga_predicted=1
| sort - dga_score
| table domain count dga_score
```

What this does: pulls DNS queries from botsv1, normalizes to the registered
domain, dedups, scores each with the model, and surfaces the most
DGA-looking ones first.

> **Field names:** botsv1's Splunk Stream DNS stores the queried name in
> `query{}` (multivalue). If your extraction differs, swap the `eval domain=`
> line for `| eval domain=lower(query)` or inspect fields with
> `index=botsv1 sourcetype=stream:dns | head 1 | fields *`.

> **Honest expectation:** botsv1 is a web-defacement + ransomware scenario,
> not a DGA-heavy botnet capture, so don't expect a tidy list of known DGA
> C2 domains. The POC's point is showing the **AITK → DSDL → container**
> round trip working at scale on real telemetry and ranking the most
> anomalous-looking domains for a human to triage.

## Optional — schedule it as a detection

Wrap Step 4 as a saved search and emit a notable/alert when
`is_dga_predicted=1 AND dga_score>0.9`, so the model runs continuously over
new DNS data. That's the natural next step from POC to a real detection.
