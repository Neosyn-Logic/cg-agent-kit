#!/usr/bin/env bash
# Prompts 1 and 2 against one model, reporting the single question that matters:
# does the model call cg_lint on its own, or does it have to be told?
#
#   ./run_lint_probe.sh qwen3.6:35b-a3b
set -uo pipefail
MODEL="${1:?usage: ./run_lint_probe.sh <ollama-model>}"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV=/home/nicolas06/brane/accelone/accelone-orchestrator/.venv/bin/activate
JAR=/home/nicolas06/neosyn/neosyn-studio/releng/lsp-server/target/cg-language-server.jar

cd "$KIT"
# shellcheck disable=SC1090
source "$VENV"
export CG_LLM_MODEL="$MODEL"
export CG_LLM_URL=http://localhost:11434/v1
export CG_OLLAMA_URL=http://localhost:11434/api/chat
export CG_JAR="$JAR"

P1="Write a C⏚ task that adds its input to a running total and outputs it, with a self-checking test. Verify it."
P2="Write a C⏚ task that adds its input to a running total and outputs it, with a self-checking test, and tell me whether it is correct."

slug="$(echo "$MODEL" | tr ':/.' '___')"
echo "=============================================================="
echo "MODEL: $MODEL"
echo "=============================================================="

for n in 1 2; do
  case $n in 1) P="$P1";; 2) P="$P2";; esac
  log="/tmp/lintprobe_${slug}_p${n}.log"
  timeout 800 python3 cg_local_client.py "$P" > "$log" 2>&1
  rc=$?
  lint=$(grep -c "cg_lint" "$log" || true)
  calls=$(grep -oE "tool_calls=[0-9]+" "$log" | tail -1 | cut -d= -f2)
  simok=$(grep -oE "simulated_ok=(True|False)" "$log" | tail -1 | cut -d= -f2)
  steps=$(grep -cE "^  step " "$log" || true)
  fails=$(grep -cE "ok=False" "$log" || true)
  printf "prompt %d: exit=%-3s steps=%-3s tool_calls=%-4s ok=False x%-3s simulated_ok=%-6s cg_lint_calls=%s\n" \
      "$n" "$rc" "$steps" "${calls:-?}" "$fails" "${simok:-?}" "$lint"
  # first distinct errors, to see whether it is the same one repeatedly
  grep -oE "'message': \"[^\"]+\"" "$log" | sort | uniq -c | sed 's/^/           /' | head -4
  echo "           log: $log"
done
echo
