# Using JupyterLab in DSDL

How to develop and run models in the DSDL "golden image" container through
JupyterLab. This is where the Python/TensorFlow code actually lives; Splunk
just streams data to it and reads results back.

> Prereqs: the lab is up ([`SETUP.md`](SETUP.md)) and the DSDL Setup page is
> saved ([`DSDL-SETTINGS.md`](DSDL-SETTINGS.md)). The golden container runs as
> the compose service **`mltk-dev`** (no need to start one from DSDL).

---

## 1. Open JupyterLab

In this lab the golden image runs as the compose-managed container
**`mltk-dev`** in **DEV mode** — that's what makes it launch JupyterLab (a
plain run only starts the API). It's already up if `docker ps` shows
`mltk-dev` with `0.0.0.0:8888->8888`.

Open: **`https://localhost:8888`**  ← **HTTPS, not http**

- It serves **HTTPS** (self-signed dev cert). Plain `http://localhost:8888`
  gives *"localhost didn't send any data"* — that's the #1 gotcha. Use
  `https://` and click through the browser's certificate warning
  (Advanced → Proceed).
- **Password:** `splunkdsdl` (set via `JUPYTER_PASSWD` in the compose file;
  change it there if you like).

| URL | What |
|---|---|
| `https://localhost:8888` | JupyterLab — develop notebooks (HTTPS!) |
| `https://localhost:5000` | the model API (Splunk calls this; you don't open it) |
| `http://localhost:6006` | TensorBoard (plain HTTP) |

> **Don't** also "Start" a container from the DSDL Containers page — compose
> already runs `mltk-dev` on ports 5000/8888/6006, and a second container
> would collide on those ports. DSDL's `fit/apply` reaches `mltk-dev` via the
> Endpoint URL (`host.docker.internal:5000`) you saved on the Setup page.

---

## 2. How DSDL maps notebooks → searchable algorithms

This is the key mental model. The tree below is **expanded for clarity** — in
the JupyterLab file browser the root `/srv` only shows the top-level folders
(`app`, `mlruns`, `notebooks`, `notebooks_backup_5.2.0`, `README.md`,
`version.md`); **double-click into a folder** to see its files.

```
/srv/                              ← the mltk-container-data volume (persists)
├── notebooks/                     ← ~40 example notebooks ship here, incl:
│   ├── barebone_template.ipynb        copy this to start a new model
│   ├── dga_train.ipynb                a built-in DGA example (bonus!)
│   ├── detect_dns_data_exfiltration_using_pretrained_model_in_dsdl.ipynb
│   ├── dga_neural_network.ipynb       ← YOUR notebook — not here until you add it
│   └── data/                          staged data + sample train.csv/test.csv
│       ├── <name>.csv                 data Splunk staged for you (dev)
│       └── <name>.json                the params Splunk sent
└── app/
    └── model/
        ├── <name>.py              ← compiled from the notebook's tagged cells
        └── data/<name>/           ← saved/trained models (from save())
```

> The golden image bundles ready-made examples — including **`dga_train.ipynb`**
> and `detect_dns_data_exfiltration_*` with sample DGA data — so you can study
> DSDL's own DGA approach before (or instead of) loading this repo's
> `dga_neural_network.ipynb`.

- A search `... | fit MLTKContainer algo=dga_neural_network ...` calls
  **`/srv/app/model/dga_neural_network.py`**.
- That `.py` is **generated from the notebook** `dga_neural_network.ipynb`
  by extracting the cells tagged with the magic comments
  `# mltkc_import`, `# mltkc_init`, `# mltkc_fit`, `# mltkc_apply`,
  `# mltkc_save`, `# mltkc_load`, `# mltkc_summary`.
- The conversion runs **on notebook save** (a Jupyter save hook). So the loop
  is: *edit cells → Save → the `.py` is rebuilt → re-run your search.*

Only code inside the tagged cells becomes part of the model. Scratch cells
(plots, `print`, experiments) are ignored by the compiler — handy for
iterating.

### The seven functions DSDL calls

| Cell tag | Function | When it runs |
|---|---|---|
| `# mltkc_import` | imports | always (top of module) |
| `# mltkc_init` | `init(df, param)` | build/return the model object |
| `# mltkc_fit` | `fit(model, df, param)` | train; return summary info |
| `# mltkc_apply` | `apply(model, df, param)` | score; return a DataFrame |
| `# mltkc_save` | `save(model, name)` | persist after fit |
| `# mltkc_load` | `load(name)` | reload before apply |
| `# mltkc_summary` | `summary(model)` | `| summary algo=...` |

`param` carries the search options — `param['options']['params']` (your
`epochs=`, etc.), plus `feature_variables` / `target_variables` (the
`X from Y` fields).

---

## 3. The development loop

### a) Stage real data from Splunk into the notebook

From the Splunk search bar, `mode=stage` sends the data + params to the
container and writes `notebooks/data/<name>.{csv,json}` **without training**:

```spl
| inputlookup dga_training_domains.csv
| fit MLTKContainer mode=stage algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model
```

### b) Iterate in JupyterLab

Open the notebook and use the dev-only `stage()` helper to load exactly what
Splunk sent, then run the functions by hand:

```python
df, param = stage("dga_neural_network")
model = init(df, param)
print(fit(model, df, param))      # trains; watch loss/accuracy
print(apply(model, df.head(20), param))
print(summary(model))
```

Tweak the model cells, re-run, repeat. This is normal interactive Jupyter —
no Splunk round trip needed while experimenting.

### c) Save → run for real from Splunk

When happy, **Save** the notebook (rebuilds the `.py`), then from Splunk:

```spl
# train + persist the model
| inputlookup dga_training_domains.csv
| fit MLTKContainer algo=dga_neural_network epochs=25 is_dga from domain into app:dga_model

# score new data
index=botsv1 sourcetype=stream:dns message_type=Query
| eval domain=lower(mvindex('query{}',0))
| stats count by domain
| apply dga_model
```

---

## 4. Loading the DGA notebook (this repo)

Two ways to get [`dga/dga_neural_network.ipynb`](../dga/dga_neural_network.ipynb)
into the container:

- **Recommended:** in JupyterLab, **copy `barebone_template.ipynb` →
  `dga_neural_network.ipynb`**, then paste each `# mltkc_*` cell from this
  repo's notebook over the template's matching cell. Save. (This guarantees
  the save-hook plumbing is wired up.)
- **Or** drag-and-drop / upload `dga_neural_network.ipynb` into
  `/srv/notebooks/` via the JupyterLab file browser; the cell tags are
  already correct. If the `.py` isn't generated, open the notebook and Save
  once to trigger the hook.

Full train/score walkthrough: [`dga/README.md`](../dga/README.md).

---

## 5. Talking to Splunk *from* the notebook (optional)

These need the matching sections enabled on the DSDL Setup page (see
[`DSDL-SETTINGS.md`](DSDL-SETTINGS.md) §6–7) and a **container restart**
afterwards.

- **Pull data with the interactive search bar** — `barebone_template`
  includes a Splunk search widget that uses the Python SDK. Requires
  **Splunk Access** = enabled (token + `host.docker.internal:8089`).
- **Push results back** — the `SplunkHEC` helper in the template posts events
  to Splunk's HEC. Requires **Splunk HEC** = enabled (token +
  `https://host.docker.internal:8088`).

For the DGA POC neither is required — `fit`/`apply` move the data for you.

---

## 6. TensorBoard (optional)

If a model writes TensorBoard logs (e.g. via a Keras `TensorBoard` callback
pointing at `/srv/notebooks/logs` or `/srv/tensorboard`), open
`http://localhost:6006`. The current DGA notebook doesn't enable TB; add a
callback in `fit()` if you want training curves.

---

## 7. Persistence & gotchas

- **Notebooks and saved models persist** — `/srv` is backed by the
  `mltk-container-data` Docker volume, so they survive stopping/starting the
  golden container. They are **not** in this git repo (they live in the
  volume); keep your authored notebook in `dga/` and re-upload if you wipe
  the volume.
- **A stopped container can't be searched** — `fit`/`apply` fail if the
  golden container isn't running. Start it from DSDL → Containers.
- **Edited a notebook but the search still runs old code?** You forgot to
  **Save** (the `.py` only regenerates on save). Save and re-run.
- **`mode=stage` then nothing happens** — that's expected; stage only writes
  `data/<name>.{csv,json}` for dev. Run without `mode=stage` to actually
  train.
- **Restarting after changing env (passwords / Splunk Access / HEC)** — stop
  & start the container from DSDL, don't `docker restart` it; DSDL recreates
  it with the new environment.
