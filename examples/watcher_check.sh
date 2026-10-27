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
# Live unit evidence is checked first and wins over the receipt:
#   - the unit name now runs another invocation             -> IDENTITY
#   - the expected invocation is loaded and failed          -> FAILED
#   - the expected invocation is still running              -> BUSY / STALL
#   - the unit is gone (collected) or exited successfully   -> the bound receipt decides
# A collected transient unit (--collect) leaves no state behind, so a job that
# fails after writing its receipt is only caught if the unit is still loaded.
# Write the receipt as the very last step.
#
# Prints one word and exits with its code:
#   BUSY 0      expected invocation running, progress fresh (or receipt written, still exiting)
#   DONE 10     unit finished/collected and receipt bound to it says "ok": true
#   FAILED 11   bound receipt says not ok, unit failed, or unit gone without a receipt
#   IDENTITY 12 receipt or live unit belongs to another invocation, or receipt unreadable
#   STALL 13    expected invocation running but progress missing or older than STALL_SECONDS
#   UNKNOWN 14  systemctl could not be queried; no conclusion either way
#
# Only BUSY should stay quiet. Every other result deserves a wake-up turn.
# DONE means the job claims success for itself; your acceptance gates still decide.
set -uo pipefail
unit=$1; want=$2; receipt=$3; progress=$4; stall=$5
scope=${SCOPE:---user}
systemctl=${SYSTEMCTL:-systemctl}

receipt_verdict=NONE
if [[ -e $receipt ]]; then
  receipt_verdict=$(python3 - "$receipt" "$unit" "$want" <<'PY'
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
fi

if ! props=$($systemctl $scope show -p ActiveState -p Result -p InvocationID "$unit" 2>/dev/null); then
  echo UNKNOWN; exit 14
fi
state=$(sed -n 's/^ActiveState=//p' <<<"$props")
result=$(sed -n 's/^Result=//p' <<<"$props")
inv=$(sed -n 's/^InvocationID=//p' <<<"$props")
[[ -n $state ]] || { echo UNKNOWN; exit 14; }

if [[ -n $inv && $inv != "$want" ]]; then echo IDENTITY; exit 12; fi
[[ $receipt_verdict == IDENTITY ]] && { echo IDENTITY; exit 12; }

if [[ $inv == "$want" ]]; then
  case $state in
    failed) echo FAILED; exit 11 ;;
    active|activating|deactivating|reloading)
      if [[ $receipt_verdict != NONE ]]; then echo BUSY; exit 0; fi   # receipt written, still exiting
      if [[ ! -e $progress ]] || (( $(date +%s) - $(stat -c %Y "$progress") > stall )); then
        echo STALL; exit 13
      fi
      echo BUSY; exit 0 ;;
    *) [[ $result == success ]] || { echo FAILED; exit 11; } ;;
  esac
fi

# Finished successfully or collected: only the bound receipt can say DONE.
case $receipt_verdict in
  DONE) echo DONE; exit 10 ;;
  *) echo FAILED; exit 11 ;;
esac
