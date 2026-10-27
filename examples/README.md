# Example scripts

Small, generic, dependency-free (Python 3.10+, ffmpeg/ffprobe, systemd, bash). They show the *shape* of each check; adapt paths, limits and expectations to your deployment, and freeze your adapted copy per job.

Run `./selftest.sh` first. It builds synthetic clips in a private temp dir and runs every check against good input (must PASS) and missing/mutated input (must FAIL): 25 cases, a few seconds.

| Script | What it proves |
|---|---|
| `decode_verify.py` | full clean decode of video + all audio, exact frame count, zero dup/drop, empty error log, expected audio stream count |
| `packet_compare.py` | copied tracks are packet-identical (payload hash, size, PTS, DTS, duration, order), names the differing field, fails on missing/empty streams |
| `disk_guard.py` | next stage fits above free-space floors, summed per filesystem; directory caps; optional maintenance-policy assertion |
| `atomic_publish.py` | copy → fsync → independent readback hash → read-only no-replace link; atomic catalog append that refuses duplicates |
| `run_stage.sh` | finite, resource-bounded, sleep-inhibited systemd unit with a fresh-only stage dir; prints unit + InvocationID |
| `watcher_check.sh` | quiet `BUSY`, or one of `DONE / FAILED / IDENTITY / STALL` for one exact job; receipt decides success |
| `kodi_scan_if_idle.py` | library scan only while nothing plays; verifies the new entry and that playback state stayed idle |
| `needrestart-report-only.conf` | stops package updates from restarting your long-running jobs |

Not included on purpose: disc extraction (tool- and jurisdiction-specific), Dolby Vision RPU editing (use dovi_tool directly, see `docs/04-encoding.md`), HLS preparation (belongs with your web player's repo). For those, the docs give the contract and the gates.
