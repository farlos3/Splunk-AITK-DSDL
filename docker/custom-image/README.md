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

## Alternatives

- **Just use a published image (no custom build).** Point the lab at any
  Splunkbase/DockerHub golden tag and skip building:
  ```bash
  ./setup.sh --golden-image splunk/mltk-container-golden-cpu:5.2.3
  ```
  or set `GOLDEN_IMAGE=<tag>` in `docker/.env` and recreate `mltk-dev`.
- **GPU.** Build on a GPU base instead, then enable GPU in compose:
  ```bash
  BASE=splunk/mltk-container-golden-gpu:5.2.3 ./docker/custom-image/build.sh
  ```
  (You still need an NVIDIA GPU + a `deploy.resources` reservation on `mltk-dev`,
  and `runtime = nvidia` on the DSDL side — see `docs/GUIDE.md`.)
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
