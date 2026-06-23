#!/usr/bin/env bash
# Make DSDL's LLM-RAG image (splunk/mltk-container-ubi-llm-rag, the "Agentic AI"
# tag) usable in this lab by patching two issues in app/model/llm_utils.py — the
# module every LLM algo (Standalone LLM, etc.) imports:
#
#   (1) Missing dependency. llm_utils hard-imports `llama_index.llms.bedrock`,
#       which the image never installs, so the algo fails to load and the search
#       dies with "Error in 'fit' command: MLTKC parameters: {...}" (in the
#       container log the algo stops at "model name:" with no "algo loaded from
#       module"). Fix: wrap the Bedrock import in try/except (Bedrock = None).
#       Ollama / OpenAI / Azure / Gemini are unaffected — only AWS Bedrock, which
#       this lab doesn't use.
#
#   (2) Context-window OOM. llama3.2:3b advertises a 128K context; llm_utils
#       creates the Ollama client without capping it, so llama_index asks Ollama
#       for the full 128K KV cache (~14 GB). On a low-RAM host llama-server is
#       OOM-killed and the LLM cell shows "ERROR at LLM generation: llama-server
#       process has terminated: signal: killed (status code: 500)". Fix: pass
#       context_window=8192 (plenty for log-triage prompts, fits easily).
#
# Both edits land in the persistent mltk-container-data volume, so they survive
# container restarts; the algo is re-imported on every `fit`, so no container
# restart is needed after patching. The patcher is idempotent and self-repairing
# (safe to re-run even if a previous run left the import block half-edited).
#
# Usage:
#   ./poc/mcp/fix_llm_rag_image.sh              # bedrock guard + cap context to 8192
#   CTX_CAP=16384 ./poc/mcp/fix_llm_rag_image.sh  # cap to a different size
#   CTX_CAP=0 ./poc/mcp/fix_llm_rag_image.sh     # use the model's full 128K context
#                                                # (only if Docker has ~18 GB+ RAM)
# Run it once after the LLM-RAG ("Agentic AI") container is RUNNING
# (Configuration -> Container Management).

set -euo pipefail

# Git Bash on Windows mangles Unix paths handed to docker.exe; disable that.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

echo "==> Locating the running LLM-RAG container"
CID="$(docker ps --format '{{.ID}} {{.Image}}' | awk '/ubi-llm-rag/{print $1; exit}')"
if [ -z "${CID:-}" ]; then
    echo "ERROR: no running container from splunk/mltk-container-ubi-llm-rag found."
    echo "       Start the \"Agentic AI\" image first: DSDL -> Configuration ->"
    echo "       Container Management -> Start. Then re-run this script."
    exit 1
fi
echo "    container: $CID"

# Context cap: 8192 by default (fits low-RAM hosts; identical quality for log
# triage). Set CTX_CAP=0 to use the model's full 128K context instead — only do
# that if you've given Docker enough RAM (~18 GB+) or llama-server gets OOM-killed.
CTX_CAP="${CTX_CAP:-8192}"

echo "==> Applying patches (idempotent): (1) Bedrock import guard  (2) Ollama context (CTX_CAP=$CTX_CAP)"
cat <<'PYEOF' | docker exec -i -e CTX_CAP="$CTX_CAP" "$CID" /usr/bin/python3.11 -
import os, re
TARGET = "from llama_index.llms.bedrock import Bedrock"
GUARD = [
    "try:",
    "    from llama_index.llms.bedrock import Bedrock",
    "except ModuleNotFoundError:",
    "    Bedrock = None  # patched: optional bedrock (missing in agentic-ai image)",
]
cap = int(os.environ.get("CTX_CAP", "8192"))
# matches the Ollama(...) line whether or not a previous context_window cap is present
CTX_PAT = re.compile(r"llm = Ollama\(\*\*llm_config_item, request_timeout=6000\.0(?:, context_window=\d+)?\)(?:  #[^\n]*)?")
if cap > 0:
    CTX_REPL = ("llm = Ollama(**llm_config_item, request_timeout=6000.0, "
                "context_window=%d)  # cap ctx: 128K KV cache OOMs on low-RAM host" % cap)
else:
    CTX_REPL = "llm = Ollama(**llm_config_item, request_timeout=6000.0)"
for p in ("/srv/app/model/llm_utils.py", "/srv/backup/app/model/llm_utils.py"):
    if not os.path.exists(p):
        continue
    lines = open(p).read().split("\n")
    out, i, handled = [], 0, False
    while i < len(lines):
        line = lines[i]
        if (not handled) and line.strip() == TARGET:
            while out and out[-1].strip() == "try:":   # drop any leftover try: above
                out.pop()
            out += GUARD
            handled = True
            i += 1
            while i < len(lines) and (lines[i].strip().startswith("except ModuleNotFoundError:")
                                      or "Bedrock = None" in lines[i]
                                      or lines[i].strip() == "try:"
                                      or lines[i].strip() == TARGET):
                i += 1
            continue
        out.append(line)
        i += 1
    s = "\n".join(out)
    s, n = CTX_PAT.subn(CTX_REPL, s)
    ctx_msg = ("ctx -> %d" % cap if cap > 0 else "ctx -> full (uncapped)") if n else "ctx line not found"
    open(p, "w").write(s)
    print("    patched:", p, "(bedrock:", "guarded" if handled else "n/a", "|", ctx_msg + ")")
PYEOF

echo "==> Verifying the LLM algo imports cleanly"
if docker exec -e PYTHONPATH=/srv "$CID" /usr/bin/python3.11 -c \
    "import app.model.llm_rag_ollama_text_processing" 2>/dev/null; then
    echo "    OK — algo loads. Re-run your inference (no container restart needed)."
else
    echo "    WARNING: algo still fails to import. Inspect with:"
    echo "      docker exec -e PYTHONPATH=/srv $CID /usr/bin/python3.11 -c 'import app.model.llm_rag_ollama_text_processing'"
    exit 1
fi
