#!/usr/bin/env bash
set -euo pipefail
cd /home/ds/dev/tiny-amps
export PATH="/home/ds/.local/bin:$PATH"
export ODIN_ROOT="/home/ds/.local/odin"
odin build . -o:minimal 2>&1 | tail -1
echo "---BUILD OK---"
out=$(mktemp)
start_ns=$(date +%s%N)
./tiny-amps 2>&1 | tee "$out"
exit_code=${PIPESTATUS[0]}
end_ns=$(date +%s%N)
elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
perf_line=$(grep '^PASS perf:' "$out" || true)
rm -f "$out"
echo "---"
echo "exit_code=$exit_code elapsed_ms=${elapsed_ms} $perf_line"
echo "reproduce: cd /home/ds/dev/tiny-amps && export PATH=\"\$HOME/.local/bin:\$PATH\" ODIN_ROOT=\"\$HOME/.local/odin\" && odin build . -o:minimal && ./tiny-amps"
