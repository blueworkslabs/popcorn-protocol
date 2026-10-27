# Pitfalls and lessons

Each entry: what happened, what fixed it, and how far the lesson reaches. A fix proven on one title applies to another only after you show the same condition there.

## Extraction

**Automatic service restart killed the rip.** An unattended package update triggered `needrestart`, which restarted the extraction unit mid-run. The replacement run correctly refused to overwrite the partial backup. *Fix:* manual-install policy and report-only needrestart ([long jobs](06-long-jobs.md#os-maintenance)). *Reach:* any long job on a host with unattended upgrades.

**"Fresh-run assertion failed" after a restart** means the predecessor's partial output survived, not that the disc is bad. Don't delete markers to force it; start a new identified run (and remove the partial only with permission).

**Unknown volume key.** The same disc failed under a temporary root cache but worked as the configured user. *Fix:* run the ripper as the user it was set up with. Exit code 0 without the ripper's completion line is not success. If the key really is unknown, preserve evidence and stop; no blind retries, no random key downloads, no firmware flashing.

**No proven in-place resume.** We never established a safe resume of an interrupted disc backup. Treat interrupted extraction as restart-from-fresh.

## Muxing and timestamps

**Native TrueHD lacing.** One UHD title's TrueHD track began with two Matroska blocks using native lacing whose inner frames carry no explicit timestamps. A remux assigned numeric timestamps, and the decoded PCM sample timing changed even though the packet payloads were identical. *Fix:* preserve those native laced blocks byte for byte for that title, and prove it with exact packet + decoded-PCM comparisons and negative controls. *Reach:* only sources with the same observed structure. Check for it; don't apply the patch blindly.

**Fixtures must be native bytes.** A short clip made with `ffmpeg -c copy` or `mkvmerge --split` is a normalized remux and erases exactly the lacing and timestamp quirks you need to test. Cut a fixture from complete original clusters up to the next video keyframe, fixing only segment size and dropping the stale seek index, and assert the cluster bytes are identical.

**`ffmpeg -c copy` is not a faithful remux.** By default ffmpeg shifts timestamps (`avoid_negative_ts`) when audio starts slightly negative, e.g. from encoder priming. Payloads stay identical, but every PTS/DTS moves. `-copyts` keeps them. The self-test in `examples/` shows the exact packet comparator catching this.

**Decode-to-null false alarm.** A full decode check with `-fps_mode passthrough` printed "non monotonically increasing dts" for perfectly good 23.976 fps Matroska. Cause: the encoder time base was 1001/24000, so two 1 ms-rounded timestamps landed on one tick. `-enc_time_base:v -1` (keep the demuxer time base) fixes it. Don't "fix" it by dropping `-xerror` or ignoring the error log.

**Exact DTS timestamps.** After mkvmerge, a DTS track's packet times drifted from the original's. The fractional, interpolated times from `mkvextract timestamps_v2` were the wrong input. *Fix:* feed mkvmerge a timestamp file built from the original's integer-millisecond packet times as reported by `ffprobe -show_packets`, validated as finite, integral and non-decreasing. Full strict verification still followed.

**mkvextract timestamp files have one extra line.** A `timestamps_v2` file for N frames has N+1 values: the last is the end of the final frame. At 23.976 fps the final Matroska `BlockDuration` quantizes to 41 or 42 ms. Validators that expect N lines, or an exact 41.708 ms tail, reject good files. Feed back only the first N values.

**Chapter end metadata.** A chapter-end mismatch after mux was fixed metadata-only (`mkvpropedit`), and we verified the media bytes didn't change.

**Keep finished video across metadata repairs.** When only a container/timestamp gate fails after a 10-hour encode, remux the existing elementary stream. Don't re-encode.

## Verification

**Unequal track tails.** Container duration follows the longest track. Validators that compared each HLS rendition to the container duration failed on films whose audio legitimately runs past the video. *Fix:* derive each track's endpoint from its own packets/decoded samples, keep the 0.3 s per-track bound. Never trim or pad to make numbers match.

**Comparators that pass by omission.** A packet comparator that iterates over the candidate's streams passes when a stream is missing. *Fix:* require both key sets to equal the expected set, require every stream non-empty, then compare (`examples/packet_compare.py`). The same goes for hashes that skip state and runners that accept 0/0 items.

**A probe's zero.** A counter that reports 0 problems is evidence only after it reported >0 on a forced positive case. Re-check what its key means after you change the data model.

**Pre-existing source damage.** One SDR disc had a decode error in the source itself. It was accepted for that title after strict output checks and a human spot-check around the timestamp, recorded as a per-title exception. The source wasn't "repaired by assertion", and the exception doesn't extend to other titles.

**Duplicated leading frame.** A CFR conversion filled a leading timestamp gap by duplicating a frame, which broke exact frame counts. *Fix:* `-fps_mode vfr` with the source time base; no frame invention.

## Delivery and clients

**Mislabeled test clip.** A "PCM baseline" clip was really sending AC-3 according to the player log. Label by what the log says is sent.

**`.nomedia` ignored for known folders.** Kodi kept rescanning a known test folder. `<excludefromscan>` in `advancedsettings.xml` fixed it after the next launch.

**Never check during playback.** The human was watching while delivery was being verified. Read-only JSON-RPC property reads are fine; scans, restarts, seeks or track changes are not.

## Operations

**Stale watcher payloads.** A watcher's stored description still named the predecessor unit after a continuation launched. Follow the current checker and checkpoint, and update the stale metadata you own.

**Another notifier is rarely the answer.** We added an update notifier and then found the morning health check already covered OS updates for one host. We extended that check to both hosts instead.
