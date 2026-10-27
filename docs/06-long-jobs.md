# Long-running jobs

A UHD title can take most of a day: extraction, fixture, encode, two full-film verifications, archive readback, delivery. Plan for interruptions, session restarts and a different agent turn picking it up.

## Workers

- One finite **systemd unit** per stage or per pipeline generation (`systemd-run` transient or a templated unit). See `examples/run_stage.sh`.
- Limits: `RuntimeMaxSec`, `CPUQuota`, `MemoryMax`, `IOWeight`/`Nice`, a sleep inhibitor (`systemd-inhibit --what=sleep`).
- **Fresh-only outputs:** the worker refuses an existing destination. A failed fresh-only job is *not* resumed by restarting its unit or deleting its markers. Reconcile what survived and launch a separately identified continuation.
- **Frozen tools:** copy the scripts a run uses into their own read-only tool generation (separate from the fresh stage dir), record their SHA-256 and external tool versions (`ffmpeg -version`, `mkvmerge -V`, `dovi_tool --version`, ripper version). Never edit a running job's files.
- **Locks:** a per-resource `flock` (optical drive, media worker, archive writes). Never bypass a held lock or queue owner.
- Prefer the unit's own graceful stop over process-name kills (`pkill -f` can match your own shell). Kill by recorded PID/cgroup only.
- Run media work at lower priority than playback: a running movie must never stutter because of a verify pass.

## Watchers

A watcher is a cheap, read-only predicate run on a schedule (`examples/watcher_check.sh`):

- Quiet while the exact unit + InvocationID is progressing. No model turn per tick when healthy.
- Wakes on success, failure, unexpected identity (different InvocationID, unit vanished), or stall (no byte/frame progress within a bound).
- Success comes from a **receipt bound to the job's identity**: the job writes `unit` (`$STAGE_UNIT` from `examples/run_stage.sh`) and `invocation_id` (systemd's `$INVOCATION_ID`) into it as its last step. An unbound receipt, or one from an earlier invocation, must never count as done; an old file at the right path is exactly how a replacement job gets "accepted" by mistake.
- Disarms itself after a successful completion turn; never duplicate a watcher just because inspection was briefly unavailable.
- systemd states can mislead: `active (exited)` may be a finished oneshot; `activating (start)` may be a long-running oneshot, not a hang. Neither proves acceptance; only the receipt does.

## Checkpoints

Write a checkpoint (`templates/CHECKPOINT.md`, `templates/job.json`) after every meaningful transition, and keep dated immutable copies. It must let a fresh agent continue **without the chat history**:

- authority and current intent; state (`RUNNING | WAITING | PAUSE_REQUESTED | PAUSED | FAILED | COMPLETE`);
- host, unit scope, exact unit, InvocationID, PID; tool hashes;
- last independently accepted stage with receipt/hash; inputs/outputs with identities;
- intentionally deleted artifacts (so nobody "restores" them);
- watcher IDs and config; capacity and reservations;
- exact next permitted action and the steps that must not be rerun;
- **what this checkpoint does NOT prove.**

A copied snapshot must not silently become a current fact. Live unit state and current receipts outrank any note.

## Pause and resume

**Pause at a boundary (preferred):**

1. Record the requested boundary (after this stage / this film / immediately). Don't guess.
2. Refresh the worker and watcher state, save a checkpoint.
3. Stop *new* stages through the continuation owner. Disabling future triggers doesn't cancel a turn already in flight; coordinate it.
4. At the boundary, independently verify the terminal state and receipt.
5. Disable only the watcher whose automatic work is now parked; decide separately about other owners (e.g. a deferred-device task).
6. Record `PAUSED`, time, authorizing request, preserved artifacts, outstanding work, resume condition.

**Immediate stop (only on request):** capture unit/InvocationID/progress/receipts first; stop the unit's control group gracefully; verify children exited and locks released. A stopped encode may not be resumable. Don't use `SIGSTOP` as a long pause: locks, reservations and deadlines become ambiguous.

**Resume:**

1. Read the checkpoint, the decisions and the acceptance contract. Old "ACTIVE" headings are history.
2. Read live unit state. If something is unexpectedly running, adopt and observe it; **never launch a duplicate**. After a reboot transient units are gone; reconcile from receipts and the filesystem, don't invent the old invocation.
3. Confirm input hashes, tool hashes and intentional deletions. Re-verify the physical disc if extraction is next.
4. Recompute peak space across stages and other host use. Check maintenance policy, locks and other workers.
5. Choose the smallest valid continuation (pending check, metadata remux, archive copy, device import, new extraction). Reuse accepted artifacts.
6. A new worker gets a new fresh stage, pinned tools, exact gates, an explicit owner. Repoint the watcher to the new InvocationID.
7. Mark `RUNNING` only after observing real progress (bytes, frames, verification reads).

## OS maintenance

We lost a multi-hour extraction because the distro's unattended upgrade installed a library update and `needrestart` then restarted the extraction service. `Restart=no` does not block an externally requested restart.

Recommended for a media host:

- Disable automatic installs (mask `apt-daily-upgrade.timer`/`.service`; hold snap refreshes if snaps are present), keep metadata refresh on.
- Make `needrestart` report-only: `$nrconf{restart} = 'l';` in `/etc/needrestart/conf.d/` (`examples/needrestart-report-only.conf`). This stops needrestart's own restarts only; a package's maintainer scripts or an admin can still restart a service, which is one more reason to install updates only when nothing is running.
- Fold "updates available, security highlighted" into an existing daily health report instead of adding another notifier.
- Install updates manually, with the human's OK, at a time no job or movie is running.
- Assert this policy in every worker's preflight (see `examples/disk_guard.py --check-maintenance`).

## Heat

Long x265 runs keep a CPU near its limit for hours. Watch temperatures and throttling. If the human wants cooler sustained temps, lowering the job's CPU quota works live (slower, same quality); fan curves often need a BIOS change and a reboot that only the human schedules.

## Backups

- The pipeline project (docs, checkpoints, frozen tools) goes into your normal off-host backup. A local git bundle is not off-host until a backup run has verifiably included it.
- Media, credentials and client databases are backed up through their own systems, not git.
- Restore to a *new* checkout and treat restored checkpoints as stale until live state is rechecked.
