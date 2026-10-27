#!/usr/bin/env bash
# Launch one pipeline stage as a finite, bounded systemd unit and print its identity.
#
#   run_stage.sh UNIT_NAME STAGE_DIR -- command args...
#
# Lifecycle:
#   1. Freeze the scripts this run uses into their own immutable tool generation
#      (e.g. /srv/work/tools/gen-0007, read-only, with a SHA-256 manifest) and point
#      the command at them. Don't put tools into STAGE_DIR, and never edit a
#      generation a running job uses.
#   2. This script creates STAGE_DIR atomically (plain mkdir: the parent must
#      exist, the leaf must not), so two admissions can't share one stage.
#   3. The job writes STAGE_DIR/receipt.json as its last step, including
#      "unit": $STAGE_UNIT (set by this script) and "invocation_id":
#      $INVOCATION_ID (set by systemd).
#      See watcher_check.sh.
#
# Sleep inhibition is on by default for system units only: user units usually
# lack the polkit right. INHIBIT=0/1 overrides; the printed JSON says which applied.
# Without it, keep the host awake another way while a job runs.
# SCOPE=--system for system units (needs root); `systemd-run --user` needs a
# lingering user session (loginctl enable-linger).
set -euo pipefail
unit=$1; stage=$2; shift 2
[[ ${1:-} == -- ]] && shift
mkdir -- "$stage" || { echo "refusing: cannot create fresh stage $stage (exists or no parent)" >&2; exit 2; }
scope=${SCOPE:---user}
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
  -E STAGE_UNIT="$unit" -E STAGE_DIR="$stage" \
  -p StandardOutput=append:"$stage/stdout.log" \
  -p StandardError=append:"$stage/stderr.log" \
  "${inhibit[@]}" "$@" 2>&1)
echo "$out" >&2
# Take the InvocationID from systemd-run itself: a fast-failing unit may already be collected.
inv=$(sed -n 's/.*invocation ID: \([0-9a-f]*\).*/\1/p' <<<"$out")
[[ -n $inv ]] || { echo "could not read InvocationID" >&2; exit 3; }
printf '{"unit":"%s","scope":"%s","invocation_id":"%s","stage":"%s","receipt":"%s/receipt.json","sleep_inhibited":%s}\n' \
  "$unit" "${scope#--}" "$inv" "$stage" "$stage" "$([[ ${#inhibit[@]} -gt 0 ]] && echo true || echo false)"
