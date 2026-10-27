#!/usr/bin/env bash
# Launch one pipeline stage as a finite, bounded systemd unit and print its identity.
#
#   run_stage.sh UNIT_NAME STAGE_DIR -- command args...
#
# - refuses an existing STAGE_DIR (fresh-only), then creates it
# - copies nothing for you: freeze your scripts into STAGE_DIR/tools first and
#   point the command at them
# - sleep inhibition on by default for system units (INHIBIT=0/1 overrides)
# - prints unit, InvocationID and the receipt path for your checkpoint/watcher
#
# Tune the limits for your host. Use --user units if you don't need root;
# `systemd-run --user` needs a lingering user session (loginctl enable-linger).
set -euo pipefail
unit=$1; stage=$2; shift 2
[[ ${1:-} == -- ]] && shift
[[ -e $stage ]] && { echo "refusing: $stage exists (fresh-only stage)" >&2; exit 2; }
mkdir -p "$stage"
scope=${SCOPE:---user}   # SCOPE=--system for system units (needs root)
# Sleep inhibition needs polkit rights; system units have them, user units usually don't.
inhibit=()
if [[ ${INHIBIT:-$([[ $scope == --system ]] && echo 1 || echo 0)} == 1 ]]; then
  inhibit=(systemd-inhibit --what=sleep --why="media stage $unit")
fi

out=$(systemd-run $scope --unit="$unit" --collect \
  -p RuntimeMaxSec="${RUNTIME_MAX:-24h}" \
  -p CPUQuota="${CPU_QUOTA:-400%}" \
  -p MemoryMax="${MEMORY_MAX:-8G}" \
  -p IOWeight=50 -p Nice=10 \
  -p WorkingDirectory="$stage" \
  -p StandardOutput=append:"$stage/stdout.log" \
  -p StandardError=append:"$stage/stderr.log" \
  "${inhibit[@]}" "$@" 2>&1)
echo "$out" >&2
# Take the InvocationID from systemd-run itself: a fast-failing unit may already be collected.
inv=$(sed -n 's/.*invocation ID: \([0-9a-f]*\).*/\1/p' <<<"$out")
[[ -n $inv ]] || { echo "could not read InvocationID" >&2; exit 3; }
printf '{"unit":"%s","scope":"%s","invocation_id":"%s","stage":"%s","receipt":"%s/receipt.json"}\n' \
  "$unit" "${scope#--}" "$inv" "$stage" "$stage"
