#!/usr/bin/env bash
# Bring up the local Ollama backend for DSDL's LLM Integrations and pull a model.
#
# This is just the §5.1 commands wrapped up: it starts the `ollama` compose
# service, waits for its API, pulls a model, and smoke-tests it. The DSDL side
# (start the LLM-RAG container, fill the Setup LLM Integrations page) is still
# done in the UI — see ../../docs/GUIDE.md#5-llm-integrations-and-mcp
# and ./README.md.
#
# Usage:
#   ./poc/mcp/setup_llm.sh                 # pull the default model (llama3.2:3b)
#   ./poc/mcp/setup_llm.sh llama3.1:8b     # pull a different model
#   MODEL=llama3.1:8b ./poc/mcp/setup_llm.sh
#   GPU=0 ./poc/mcp/setup_llm.sh           # force CPU (default: auto-detect NVIDIA GPU)

set -euo pipefail

# Git Bash on Windows mangles Unix paths passed to docker.exe; disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

MODEL="${1:-${MODEL:-llama3.2:3b}}"

# Run from the repo root (two levels up) and use a RELATIVE compose path — a
# Git-Bash-style absolute path (/d/...) gets mangled when handed to docker.exe.
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
OLLAMA_URL="http://localhost:11434"

echo "==> Checking Docker is running"
docker info >/dev/null 2>&1 || { echo "ERROR: Docker isn't reachable. Start Docker Desktop and retry."; exit 1; }

# Use the NVIDIA GPU for Ollama when available (layers in docker-compose.gpu.yml).
# Auto-detected; force with GPU=1 / GPU=0. Macs / GPU-less hosts run on CPU.
COMPOSE_ARGS=(-f docker/docker-compose.yml)
USE_GPU="${GPU:-}"
[ -z "$USE_GPU" ] && { docker run --rm --gpus all alpine true >/dev/null 2>&1 && USE_GPU=1 || USE_GPU=0; }
if [ "$USE_GPU" = "1" ]; then
    COMPOSE_ARGS+=(-f docker/docker-compose.gpu.yml)
    echo "    GPU: enabled for Ollama (NVIDIA)"
else
    echo "    GPU: off — Ollama on CPU"
fi

echo "==> Starting the ollama service"
docker compose "${COMPOSE_ARGS[@]}" up -d ollama

echo "==> Waiting for the Ollama API on $OLLAMA_URL"
for i in $(seq 1 30); do
    if curl -fs "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
        echo "    API is up."
        break
    fi
    [ "$i" -eq 30 ] && { echo "ERROR: Ollama API didn't come up in time."; exit 1; }
    sleep 2
done

echo "==> Pulling model: $MODEL  (first pull downloads a few GB)"
docker exec ollama ollama pull "$MODEL"

echo "==> Installed models:"
docker exec ollama ollama list

echo "==> Smoke test"
curl -fs "$OLLAMA_URL/api/generate" \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"reply with: ok\",\"stream\":false}" \
    | sed 's/.*"response":"\([^"]*\)".*/    model replied: \1/' || true

cat <<EOF

Done. Ollama is serving "$MODEL" at $OLLAMA_URL.

Next, in the DSDL app (these stay in the UI):
  1. Configuration -> Container Management : start "Agentic AI"
       (NOT "Red Hat LLM RAG CPU" :5.2.4 — it crashes on boot, missing langgraph)
  2. Configuration -> Setup LLM Integrations (LLM block):
       LLM Service  = Ollama        Enable Ollama = Yes
       Ollama URL   = http://host.docker.internal:11434
       Model Name   = $MODEL
  3. Assistants -> LLM Chat : run a search, pick the model, ask away.

Walkthrough: poc/mcp/README.md
EOF
