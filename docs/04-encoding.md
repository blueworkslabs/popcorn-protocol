# Encoding profiles

These are the profiles that passed our gates and suited our clients. Treat them as a starting point. Changing a quality profile is a decision for your human, not a silent tuning step, and never retune an active worker.

## UHD original edition

Remux only. Native HEVC base layer plus the Dolby Vision enhancement layer/RPU (profile 7 discs carry BL+EL), every intended source audio track bit-exact (TrueHD/Atmos, DTS-HD MA, AC-3), intended subtitles (PGS), chapters. No re-encode, no audio conversion.

## UHD streaming edition (1080p, DV 8.1 + HDR10)

For TV sticks and the handheld. Measured baseline:

- Video: 1080p HEVC Main10, `libx265 -preset fast`, nominal 6 Mb/s, max 8 Mb/s (`-b:v 6M -maxrate 8M -bufsize 8M`), `open-gop=0`, `repeat-headers=1`.
- Scaling: `zscale=w=1920:h=1080:filter=lanczos,format=yuv420p10le,setsar=1`. Keep letterbox bars (no crop) so the DV active-area metadata can be scaled instead of re-derived.
- HDR10: `hdr10=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:range=limited:master-display=<measured>:max-cll=<measured>`. Read `master-display` and `max-cll` from the source's first-frame side data (`ffprobe -show_frames -read_intervals %+#1`). **Never copy them from another title.**
- Timing: `-fps_mode passthrough` with the source time base (e.g. `-enc_time_base:v 1001:24000`) so no frames are dropped or invented.
- Dolby Vision, with [dovi_tool](https://github.com/quietvoid/dovi_tool):
  1. `extract-rpu` from the original; `info -s` to record profile and frame count (must equal the video frame count).
  2. Convert to profile 8.1 with the editor (`mode: 2`). Scale L5 active-area offsets for 2160→1080: `ceil(source/2)`, no image crop. Verify the edit's frame range covers exactly `0..N-1`.
  3. Encode the HEVC elementary stream, then `inject-rpu`.
  4. Verify: DV profile 8, RPU present, no EL, BL compatibility id 1, RPU frame count = N, re-extracted RPU equals the injected one.
- Mux with `mkvmerge`: the new video plus audio/subtitles/chapters **copied from the original**. Copied tracks must still pass the exact packet comparison. Pass explicit per-track timestamp files where mkvmerge would otherwise re-quantize (see [pitfalls](07-pitfalls.md)).

## 1080p Blu-ray (SDR) library edition

Usually keep the original AVC video as is. Keep every original audio track. If the audio chain can't decode the lossless formats, *add* a compatible track, don't replace:

- E-AC-3 (DD+) 5.1 at 1024 kb/s, or AC-3 5.1 at 640 kb/s, derived from the primary lossless track;
- mark the compatible track default; keep TrueHD/DTS-HD after it;
- a DD+ derived from Atmos is not Atmos. Say so.

Run a listening comparison with your human before adding compatibility tracks to the whole library. We found no audible benefit from DD+ over the existing AC-3 on our soundbar and stopped generating it.

## SDR browser HLS

For a browser/phone page, separate from the Kodi libraries. Source: original-quality SDR only. HDR input is rejected, not tone-mapped silently.

- Video: 720p H.264 High@4.0, NVENC `p6 -tune hq -rc vbr -cq 21 -b:v 3M -maxrate 4M -bufsize 8M`, `yuv420p`, **no B-frames** (keeps separately packaged audio/video timelines aligned), keyframe every 6 s (`-force_key_frames expr:gte(t,n_forced*6)`), `-fps_mode vfr` with the source time base (no duplicated frames to fill leading gaps). Native 24 fps stays 24, 23.976 stays 23.976.
- Audio per language: AAC-LC stereo 160 kb/s and AC-3 5.1 448 kb/s, 48 kHz, `aresample=async=1:first_pts=0`.
- Packaging: fMP4 HLS, 6 s segments, VOD playlists, `independent_segments`. Two master playlists: `stereo.m3u8` (AAC group) and `surround.m3u8` (AC-3 group); start in stereo, fall back to stereo on a fatal codec error.
- Validation (the canonical tools live with the web app):
  - complete playlists, every segment present, codecs and channel counts as declared;
  - **exact source frame count** decoded from the video rendition, zero dup/drop;
  - each audio rendition's decoded endpoint within 0.3 s of *its own* source track's packet timeline (not the container duration: unequal tails are legal, truncation is not);
  - output start within 50 ms;
  - full clean decode of every rendition.
- Publish into the export with a no-replace directory move on the same filesystem, then atomically replace `catalog.json`.
- Origin: a minimal read-only server bound to the LAN, source-IP allowlist for the app host, explicit file allowlist (playlists, `init.mp4`, segments, artwork), byte ranges, no directory listing, no symlink escape. `Cache-Control: no-store`; the page's service worker never caches movie content.
- Browser player: native HLS on Apple browsers, bundled hls.js elsewhere (don't trust Chromium's `canPlayType` for HLS). Decoding AC-3 in a browser does not prove six-channel output.

## Performance work

Measure before tuning. Per stage: wall time, bytes, frames, encoder fps, CPU utilization **and cgroup quota throttling**, memory pressure, per-disk latency/queue, temperature, other consumers. Whole-job averages hide the bottleneck. A CPU quota that helped one codec/thread profile doesn't transfer to another. Evaluate a faster preset or hardware HEVC only as a separate quality experiment on matched clips with full acceptance; don't promise a speedup in advance.
