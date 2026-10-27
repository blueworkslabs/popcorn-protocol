# Standard workflow

A stage advances on its **receipt**, never because a command exited or a percentage hit 100.

## 1. Intake and admission

- Address the drive by its stable `/dev/disk/by-id/` path; resolve the current device node and the ripper's drive index fresh every time.
- Verify disc label/UUID, edition and title inventory (playlists, sizes). Never infer the next disc from the previous one: the human may have swapped trays while you were encoding.
- Admission checks: maintenance policy (no auto-restarts, see [long jobs](06-long-jobs.md)), drive idle, no conflicting units, locks free, aggregate storage budget OK.
- Hardware care: some drives have a manual cover or fragile tray mechanism. Ask before any software eject. Don't flash drive firmware as routine recovery.

## 2. Extract to a fresh stage

- Run the ripper as the user whose config/cache it was set up with. Running it as a different user (e.g. root via sudo) can fail on keys the configured user resolves fine.
- Wrap it in a supervisor: frozen tool versions, exact input identity, **fresh-only destination** (refuse if it exists), finite overall/child/stall deadlines, CPU/memory/IO bounds, a sleep inhibitor, live free-space guards.
- Record unit scope (system/user), unit name and **InvocationID**. Point the watcher at that exact invocation.
- Receipt: exit 0 **and** the ripper's own completion line (e.g. `Backup done`), no read/SCSI/hash errors in the log, every inventoried file present at expected size, a full SHA-256 manifest of the saved files with stable identities, a strict decode of representative video and **all** audio streams.
- This proves a saved extraction, not an acceptable film.
- If interrupted and no in-place resume is proven: start a fresh run with a new identity. Remove only the unusable partial data you were explicitly allowed to remove; keep small diagnostics.

## 3. Relocate (if the backup must move tiers)

Budget for source and destination coexisting. Copy with source hash, read the destination back fully and hash independently, verify membership/size/identity and no open consumers. Only then retire the exact verified source files. Keep receipts; don't recreate intentionally retired stages from old notes.

## 4. Prepare the original

From the accepted backup, derive *for this disc*: main playlist and segments, edition, chapters, languages, audio/subtitle tracks, cadence, expected frame count. Preserve native UHD video including the Dolby Vision enhancement layer and RPU, intended audio/subtitles and chapters. Never copy another title's counts or HDR values.

## 5. Prove a native-source fixture

Before a multi-hour full run, cut a short fixture from the **actual source bytes** (complete clusters, not a normalized remux; see `docs/07-pitfalls.md` on lacing) and run the whole pipeline on it:

- copied audio: packet payload, order, count, PTS, DTS, duration identical; decoded PCM and sample timing identical where mux behavior could change;
- video: cadence, frame count, HDR10 static metadata, DV profile/RPU;
- chapters;
- negative controls: drop a stream, mutate one payload byte, shift a timestamp → each must FAIL.

## 6. Streaming encode and full verification

Encode per [encoding profiles](04-encoding.md). The original stays untouched. Keep worker deadlines in line with measured runtime: full verification of two editions is a long phase of its own. Finished encoding is not permission to publish. If only metadata fails later, keep the completed video and remux.

## 7. Archive and publish

- Copy both accepted editions into private archive staging, read back fully, hash, verify identities.
- Publish read-only immutable names atomically and **no-replace** (`rename` with `RENAME_NOREPLACE`, or link-then-check). See `examples/atomic_publish.py`.
- Read the current catalog/library state first; never restore a stale catalog snapshot over newer entries.
- Verify HTTP delivery: HEAD size, exact byte-range hashes at start/middle/end, suffix range, 416 out of bounds, 404 unknown, write methods rejected, disallowed source IP denied, retired/private paths denied.
- Service changes need safe timing (nobody watching) and the relevant permission.

## 8. Deliver and close

- Check device/library state before touching it. Add entries through the client's supported native path (e.g. Kodi JSON-RPC library scan) and verify old records, settings, bookmarks and watched state are preserved.
- Don't interrupt games or playback. Don't claim listening quality from software checks.
- An offline device (handheld asleep) gets a separate deferred task with its import materials. It doesn't block other delivery or authorized cleanup.
- Cleanup: a reviewed exact-file manifest with in-use, identity and protected-media checks. Keep finished editions, links, import materials, reports and exception history. Retire only the watcher whose scope is finished.
- Admit the next disc only after fresh admission checks.

## SDR branch (browser HLS)

Use original-quality **SDR** sources only, never HDR/UHD and never an already-compressed streaming copy. Profile and gates: [encoding](04-encoding.md#sdr-browser-hls). Be honest about what isn't there yet (e.g. "subtitles not available in the browser").
