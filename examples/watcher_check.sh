#!/usr/bin/env bash
# Read-only watcher predicate for one exact job. Cheap enough to run every few minutes.
#
#   watcher_check.sh UNIT INVOCATION_ID RECEIPT PROGRESS_FILE STALL_SECONDS
#
# The job itself writes RECEIPT as its last step, bound to its own identity:
#   {"ok": true, "unit": "<$STAGE_UNIT>", "invocation_id": "<$INVOCATION_ID>", ...}
# systemd exports $INVOCATION_ID to every service process; run_stage.sh sets
# $STAGE_UNIT. A receipt without matching unit + invocation_id is never DONE:
# an old run's receipt or a wrong path must not advance a new job.
#
# Prints one word and exits with its code:
#   BUSY 0      unit running with the expected InvocationID, progress file fresh
#   DONE 10     receipt bound to this unit+invocation says "ok": true
#   FAILED 11   bound receipt says not ok, or unit gone/failed without a receipt
#   IDENTITY 12 receipt or running unit belongs to another invocation, or receipt unreadable
#   STALL 13    expected unit running but progress file missing or older than STALL_SECONDS
#
# Only BUSY should stay quiet. Every other result deserves a wake-up turn.
# DONE means the job claims success for itself; your acceptance gates still decide.
set -uo pipefail
unit=$1; want=$2; receipt=$3; progress=$4; stall=$5
scope=${SCOPE:---user}
systemctl=${SYSTEMCTL:-systemctl}

if [[ -e $receipt ]]; then
  verdict=$(python3 - "$receipt" "$unit" "$want" <<'PY'
import json, sys
path, unit, want = sys.argv[1:]
try:
    r = json.load(open(path))
except (OSError, ValueError):
    r = None
if not isinstance(r, dict) or r.get('unit') != unit or r.get('invocation_id') != want:
    print('IDENTITY')
elif r.get('ok') is True:
    print('DONE')
else:
    print('FAILED')
PY
)
  case $verdict in
    DONE) echo DONE; exit 10 ;;
    FAILED) echo FAILED; exit 11 ;;
    *) echo IDENTITY; exit 12 ;;
  esac
fi

state=$($systemctl $scope show -p ActiveState --value "$unit" 2>/dev/null)
inv=$($systemctl $scope show -p InvocationID --value "$unit" 2>/dev/null)
case $state in
  active|activating|reloading) ;;
  *) echo FAILED; exit 11 ;;
esac
[[ $inv == "$want" ]] || { echo IDENTITY; exit 12; }
if [[ ! -e $progress ]] || (( $(date +%s) - $(stat -c %Y "$progress") > stall )); then
  echo STALL; exit 13
fi
echo BUSY; exit 0
