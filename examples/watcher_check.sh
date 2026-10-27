#!/usr/bin/env bash
# Read-only watcher predicate for one exact job. Cheap enough to run every few minutes.
#
#   watcher_check.sh UNIT INVOCATION_ID RECEIPT PROGRESS_FILE STALL_SECONDS
#
# Prints one word and exits with its code:
#   BUSY 0      unit running with the expected InvocationID, progress file fresh
#   DONE 10     receipt exists and says "ok": true
#   FAILED 11   receipt says not ok, or unit gone/failed without an ok receipt
#   IDENTITY 12 unit running but with a different InvocationID (someone relaunched it)
#   STALL 13    expected unit running but progress file older than STALL_SECONDS
#
# Only BUSY should stay quiet. Every other result deserves a wake-up turn.
# The receipt decides success: systemd state alone never proves acceptance.
set -uo pipefail
unit=$1; want=$2; receipt=$3; progress=$4; stall=$5
scope=${SCOPE:---user}

if [[ -f $receipt ]]; then
  if python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ok") is True else 1)' "$receipt"; then
    echo DONE; exit 10
  fi
  echo FAILED; exit 11
fi

state=$(systemctl $scope show -p ActiveState --value "$unit" 2>/dev/null)
inv=$(systemctl $scope show -p InvocationID --value "$unit" 2>/dev/null)
case $state in
  active|activating|reloading) ;;
  *) echo FAILED; exit 11 ;;
esac
[[ $inv == "$want" ]] || { echo IDENTITY; exit 12; }
if [[ ! -e $progress ]] || (( $(date +%s) - $(stat -c %Y "$progress") > stall )); then
  echo STALL; exit 13
fi
echo BUSY; exit 0
