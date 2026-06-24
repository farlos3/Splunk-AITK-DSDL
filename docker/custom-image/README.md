# Custom DSDL container image (the lab's default)

This folder builds the **`mltk-dev`** container image the lab runs by default —
the DSDL "golden" image with **your own Python libraries layered on top**, so you
can add or remove packages without waiting for a new Splunk release.

It's a **thin extension**: [`Dockerfile`](Dockerfile) does `FROM` the published
golden image and `pip install`s [`requirements.extra.txt`](requirements.extra.txt).
That keeps the full DSDL container contract intact — DEV-mode JupyterLab on
`:8888`, the model API on `:5000`, the `/srv` layout — so `fit`/`apply MLTKContainer`
(the DGA POC) and JupyterLab keep working exactly as before.

| File | What it is |
|---|---|
| [`Dockerfile`](Dockerfile) | `FROM <golden>` + install the extra requirements |
| [`requirements.extra.txt`](requirements.extra.txt) | **the one place** to add/remove pip packages |
| [`build.sh`](build.sh) | build + tag `splunkaitk/mltk-container-custom:local` (local only — no registry push) |

## Add or remove a library

1. Edit [`requirements.extra.txt`](requirements.extra.txt) (one pip requirement per
   line; pin versions). The golden base already has TensorFlow, PyTorch, pandas,
   scikit-learn, JupyterLab, etc. — only list what's missing.
2. Rebuild:
   ```bash
   ./docker/custom-image/build.sh
   ```
3. Recreate just the dev container so it picks up the new image:
   ```bash
   docker compose -f docker/docker-compose.yml up -d --force-recreate mltk-dev
   ```
   (Or re-run `./setup.sh`, which rebuilds and recreates for you.)

> Notebooks and trained models live in the `mltk-container-data` volume (`/srv`),
> not in the image, so recreating `mltk-dev` does **not** lose your work.

## How the lab wires it up

`setup.sh` builds this image and writes its tag into `docker/.env` as
`GOLDEN_IMAGE=splunkaitk/mltk-container-custom:local`; the `mltk-dev` service in
[`../docker-compose.yml`](../docker-compose.yml) reads `${GOLDEN_IMAGE}`. So the
swap is transparent — only *what tag* `GOLDEN_IMAGE` holds changes.

## On macOS / a fresh machine

The custom image is a **local tag** (`splunkaitk/mltk-container-custom:local`) — it
is **not pushed to any registry**, so it only exists where you build it. Cloning
the repo onto another machine (e.g. a Mac) does **not** carry the image; you
**rebuild it there**:

- **Just run `./setup.sh`.** It builds the custom image on that machine and writes
  `GOLDEN_IMAGE` into `docker/.env` for you. (`docker/.env` is gitignored, so it
  doesn't travel with the repo — setup.sh regenerates it.) Or build directly with
  `./docker/custom-image/build.sh`.
- **If you run `docker compose up` *without* first running setup.sh** (no
  `docker/.env`), compose falls back to the **published golden** image — the lab
  still runs, just without your extra libs. Run setup.sh / build.sh to get the
  custom image.

**Apple Silicon (M1/M2/M3):** these images are `linux/amd64` (Splunk doesn't ship a
native arm64 golden), and `mltk-dev` pins `platform: linux/amd64`, so they run under
**emulation**. It works, but the first build and model runs are slower. For the best
amd64 performance turn on **Docker Desktop → Settings → General → "Use Rosetta for
x86/amd64 emulation"**, and give Docker enough memory (Settings → Resources — the
lab wants 8 GB+ free while running). **Intel Macs** run amd64 natively, no emulation.

> The bash scripts run natively on macOS (zsh/bash) — no Git Bash needed. The
> `MSYS_*` lines in the scripts are Windows-only and are harmlessly ignored elsewhere.

## Alternatives

- **Just use a published image (no custom build).** Point the lab at any
  Splunkbase/DockerHub golden tag and skip building:
  ```bash
  ./setup.sh --golden-image splunk/mltk-container-golden-cpu:5.2.3
  ```
  or set `GOLDEN_IMAGE=<tag>` in `docker/.env` and recreate `mltk-dev`.
- **GPU.** Independent of the custom image — see [GPU](#gpu) below.
- **Deep customization** (different base such as `tensorflow/tensorflow`, conda,
  RAPIDS): use Splunk's upstream build system instead of this thin extension —
  [`splunk/splunk-mltk-container-docker`](https://github.com/splunk/splunk-mltk-container-docker)
  (`build.sh <flavor> <repo>/`), then set `GOLDEN_IMAGE` to your tag.
- **Customizing the *LLM-RAG* container** (the DSDL-spawned LLM Chat / RAG / MCP
  container, **not** `mltk-dev`): that one is selected in **DSDL → Container
  Management** and registered through `mltk-container`'s `images.conf`, a separate
  mechanism. Its known boot issues are patched at runtime by
  [`../../poc/mcp/fix_llm_rag_image.sh`](../../poc/mcp/fix_llm_rag_image.sh); baking
  those fixes into a custom LLM-RAG image is the permanent alternative.

## GPU

GPU is **independent of the custom image** — it's config/tags, not a build. Ollama
uses an NVIDIA GPU **automatically**; the DGA model (`mltk-dev`) stays on CPU
(it's tiny — the GPU pays off on LLM inference, not the classifier).

**Prerequisites:** a real **NVIDIA GPU** + driver, and Docker able to reach it — on
**Windows** that means the WSL2 backend plus the **NVIDIA Container Toolkit** in
your WSL distro. **Apple Silicon and AMD GPUs do not work** here (those fall back
to CPU automatically).

### 1. Ollama (local LLM inference) — on by default

`setup.sh` (and `poc/mcp/setup_llm.sh`) **auto-detect** the GPU and layer in
[`../docker-compose.gpu.yml`](../docker-compose.gpu.yml), which adds the device
reservation to the `ollama` service. Nothing to edit; Macs / GPU-less hosts skip it
and run CPU. Verify and force on/off:

```bash
docker exec ollama nvidia-smi            # should list your GPU
./setup.sh --no-gpu                       # force Ollama onto CPU (or --gpu to force on)
GPU=0 ./poc/mcp/setup_llm.sh              # same, for the model-pull helper
```

By hand without the scripts:

```bash
docker compose -f docker/docker-compose.yml -f docker/docker-compose.gpu.yml up -d ollama
```

`llama3.2:3b` / `llama3.1:8b` get much faster. Nothing to rebuild.

### 2. golden / `mltk-dev` (DGA model + JupyterLab)

Point it at Splunk's **published GPU** golden tag instead of `-cpu` — no build
needed:

```bash
./setup.sh --golden-image splunk/mltk-container-golden-gpu:5.2.3
# or set GOLDEN_IMAGE=...golden-gpu... in docker/.env and recreate mltk-dev
```

…plus add the same `deploy.resources` GPU block to the **`mltk-dev`** service, and
set `runtime = nvidia` for DSDL-spawned containers (DSDL Setup page /
`mltk-container` `images.conf`). The DGA model is tiny, so CPU is fine for it —
path **1 (Ollama)** is where GPU actually pays off.

### GPU *and* your extra libs

Build the custom image on the GPU base, then give `mltk-dev` the reservation:

```bash
BASE=splunk/mltk-container-golden-gpu:5.2.3 ./docker/custom-image/build.sh
```
