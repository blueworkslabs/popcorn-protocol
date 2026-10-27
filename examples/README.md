# Example scripts

Small and generic, with no third-party Python packages (runtime needs: Python 3.10+, ffmpeg/ffprobe, systemd, bash). They show the *shape* of each check; adapt paths, limits and expectations to your deployment, and freeze your adapted copy per job.

Run `./selftest.sh` first. It builds synthetic clips in a private temp dir and runs the scripts against good input (must PASS) and missing, mutated or invalid input (must FAIL): 47 cases, under a minute. The suite was itself mutation-checked: breaking filesystem aggregation, number validation, the catalog lock, receipt binding, the strict Kodi idle test or incremental UTF-8 decoding each turns it red.

Not covered by the self-test: `run_stage.sh` and `disk_guard.py --check-maintenance` need a real systemd host (the watcher is tested against a fake `systemctl`). Smoke-test them by hand: launch a short job, then check `BUSY`, `IDENTITY` with a wrong InvocationID, `STALL` with an old progress file and `DONE` after its bound receipt appears.

| Script | What it proves |
|---|---|
| `decode_verify.py` | full clean decode of video + all audio, exact frame count, zero dup/drop, empty error log, expected audio stream count |
| `packet_compare.py` | copied tracks are packet-identical (payload hash, size, PTS, DTS, duration, order), names the differing field, fails on missing/empty streams |
| `disk_guard.py` | next stage fits above free-space floors, summed per filesystem; directory caps; optional maintenance-policy assertion (APT, needrestart, snap hold); fails closed on missing or invalid input |
| `atomic_publish.py` | copy → fsync → independent readback hash → read-only no-replace link; locked, atomic catalog append that refuses duplicates and survives concurrent writers |
| `run_stage.sh` | finite, resource-bounded systemd unit with an atomically created fresh-only stage dir; prints unit + InvocationID. Sleep inhibition only for system units by default (user units usually lack the polkit right) |
| `watcher_check.sh` | quiet `BUSY`, or one of `DONE / FAILED / IDENTITY / STALL` for one exact job; only a receipt bound to that unit + InvocationID can say `DONE` |
| `kodi_scan_if_idle.py` | library scan only on an explicit empty player list (null/unknown = refuse); verifies the new entry and idle state afterwards |
| `needrestart-report-only.conf` | stops needrestart from restarting your long-running jobs after updates (not package maintainer scripts or manual restarts) |

Not included on purpose: disc extraction (tool- and jurisdiction-specific), Dolby Vision RPU editing (use dovi_tool directly, see `docs/04-encoding.md`), HLS preparation (belongs with your web player's repo). For those, the docs give the contract and the gates.
