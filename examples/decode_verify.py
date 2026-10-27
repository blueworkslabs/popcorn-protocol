#!/usr/bin/env python3
"""Full clean decode of video + every audio stream with an exact frame count.

PASS requires all of:
  - the expected number of audio streams is present (omission control),
  - ffmpeg exits 0 with -xerror and an empty error log,
  - progress reaches "end",
  - decoded video frames == --frames, dup_frames == drop_frames == 0.

Usage: decode_verify.py MEDIA --frames N --audio-streams K [--receipt out.json]
Reads the whole file: expect it to take a long time on a full film.
"""
import argparse, json, subprocess, sys, tempfile, pathlib


def probe_counts(media):
    out = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'json', media],
        capture_output=True, text=True, check=True)
    types = [s['codec_type'] for s in json.loads(out.stdout)['streams']]
    return types.count('video'), types.count('audio')


def last_progress(path):
    block, last = {}, {}
    for line in pathlib.Path(path).read_text().splitlines():
        if '=' not in line:
            continue
        k, v = line.split('=', 1)
        block[k] = v
        if k == 'progress':
            last, block = block, {}
    return last


def verify(media, frames, audio_streams):
    failures = []
    videos, audios = probe_counts(media)
    if videos < 1:
        failures.append('no video stream')
    if audios != audio_streams:
        failures.append(f'expected {audio_streams} audio streams, found {audios}')
    with tempfile.TemporaryDirectory() as tmp:
        prog = pathlib.Path(tmp) / 'progress'
        cmd = ['ffmpeg', '-nostdin', '-hide_banner', '-v', 'error', '-xerror', '-i', media,
               '-map', '0:v:0', '-map', '0:a', '-fps_mode:v', 'passthrough',
               # keep the demuxer time base: with 1 ms Matroska timestamps a 1001/24000
               # encoder time base maps two frames to one tick and the null muxer errors
               '-enc_time_base:v', '-1',
               '-progress', str(prog), '-f', 'null', '-']
        run = subprocess.run(cmd, capture_output=True, text=True)
        p = last_progress(prog) if prog.exists() else {}
    if run.returncode != 0:
        failures.append(f'ffmpeg exit {run.returncode}')
    if run.stderr.strip():
        failures.append('decoder error log not empty: ' + run.stderr.strip().splitlines()[0][:200])
    if p.get('progress') != 'end':
        failures.append('progress did not reach end')
    if int(p.get('frame', -1)) != frames:
        failures.append(f"decoded {p.get('frame')} frames, expected {frames}")
    if p.get('dup_frames') != '0' or p.get('drop_frames') != '0':
        failures.append(f"dup={p.get('dup_frames')} drop={p.get('drop_frames')}")
    return dict(ok=not failures, media=media, expected_frames=frames,
                decoded_frames=p.get('frame'), audio_streams=audios, failures=failures)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('media')
    ap.add_argument('--frames', type=int, required=True)
    ap.add_argument('--audio-streams', type=int, required=True)
    ap.add_argument('--receipt')
    a = ap.parse_args()
    r = verify(a.media, a.frames, a.audio_streams)
    text = json.dumps(r, indent=2)
    if a.receipt:
        pathlib.Path(a.receipt).write_text(text + '\n')
    print(text)
    sys.exit(0 if r['ok'] else 1)
