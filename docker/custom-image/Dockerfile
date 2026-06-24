# Custom DSDL "golden" image for this lab.
#
# Thin extension of Splunk's published golden image: it keeps the entire DSDL
# container contract (entrypoint, DEV-mode JupyterLab on :8888, model API on
# :5000, the /srv layout) and just layers your extra Python libraries on top.
# Edit requirements.extra.txt, then rebuild with ./build.sh.
#
# Override the base to use a different flavour/version or a GPU build, e.g.:
#   BASE=splunk/mltk-container-golden-gpu:5.2.3 ./build.sh
ARG BASE=splunk/mltk-container-golden-cpu:5.2.3
FROM ${BASE}

# Extra Python libs for this lab — the one place to add/remove packages.
# The golden image runs as a non-root user (uid 1001) and ships pip only as a
# module (no `pip` binary on PATH), so install as root via `python3 -m pip` into
# the global site-packages, then restore the runtime user so the entrypoint
# (/dltk/bootstrap_fast.sh) still runs as 1001.
USER root
COPY requirements.extra.txt /tmp/requirements.extra.txt
RUN python3 -m pip install --no-cache-dir -r /tmp/requirements.extra.txt
USER 1001
