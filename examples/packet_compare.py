#!/usr/bin/env python3
"""Exact packet comparison for tracks copied from a reference into a candidate.

For each mapped stream pair, every packet's pts_time, dts_time, duration_time,
size and SHA-256 payload hash must match, in order. Bounded memory: packets are
streamed into digests (aggregate + one per field, so a mismatch says *which*
field differs).

Omission control: both sides must contain exactly the mapped streams with at
least one packet each; a missing or empty stream is a FAIL, never a skip.

Usage: packet_compare.py REFERENCE CANDIDATE --map 1:1,2:2 [--receipt out.json]
  --map ref_index:candidate_index (absolute ffprobe stream indices)

Caveat: *_time strings depend on each container's time base. Compare like with
like (e.g. Matroska to Matroska, both 1 ms) or compare raw pts/dts with known
time bases instead.
"""
import argparse, hashlib, json, pathlib, re, subprocess, sys

FIELDS = ('pts_time', 'dts_time', 'duration_time', 'size', 'data_hash')


def digest(media, indices):
    agg = {i: hashlib.sha256() for i in indices}
    per = {i: {f: hashlib.sha256() for f in FIELDS} for i in indices}
    count = {i: 0 for i in indices}
    p = subprocess.Popen(
        ['ffprobe', '-v', 'error', '-show_packets', '-show_data_hash', 'sha256',
         '-show_entries', 'packet=stream_index,' + ','.join(FIELDS), '-of', 'compact', media],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for line in p.stdout:
            if not line.startswith('packet|'):
                continue
            d = dict(x.split('=', 1) for x in line.rstrip('\n').split('|')[1:] if '=' in x)
            i = int(d['stream_index'])
            if i not in agg:
                continue
            if any(f not in d for f in FIELDS) or not re.fullmatch(r'SHA256:[0-9a-f]{64}', d['data_hash']) \
                    or int(d['size']) <= 0:
                raise ValueError(f'incomplete packet record in stream {i}: {line.strip()[:120]}')
            agg[i].update(('|'.join(d[f] for f in FIELDS) + '\n').encode())
            for f in FIELDS:
                per[i][f].update((d[f] + '\n').encode())
            count[i] += 1
        err = p.stderr.read()
        if p.wait() != 0 or err.strip():
            raise RuntimeError(f'ffprobe failed on {media}: {err.strip()[:200]}')
    finally:
        if p.poll() is None:
            p.kill()
    return {i: dict(packets=count[i], sha256=agg[i].hexdigest(),
                    fields={f: h.hexdigest() for f, h in per[i].items()}) for i in indices}


def stream_indices(media):
    out = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=index', '-of', 'json', media],
                         capture_output=True, text=True, check=True)
    return {s['index'] for s in json.loads(out.stdout)['streams']}


def compare(ref, cand, mapping):
    failures = []
    for media, wanted in ((ref, [r for r, _ in mapping]), (cand, [c for _, c in mapping])):
        missing = set(wanted) - stream_indices(media)
        if missing:
            failures.append(f'{media}: missing streams {sorted(missing)}')
    if failures:
        return dict(ok=False, failures=failures)
    a = digest(ref, [r for r, _ in mapping])
    b = digest(cand, [c for _, c in mapping])
    pairs = []
    for r, c in mapping:
        x, y = a[r], b[c]
        bad = [f for f in FIELDS if x['fields'][f] != y['fields'][f]]
        if x['packets'] == 0 or y['packets'] == 0:
            failures.append(f'{r}:{c} empty stream')
        if x['packets'] != y['packets']:
            failures.append(f"{r}:{c} packet count {x['packets']} != {y['packets']}")
        if x['sha256'] != y['sha256']:
            failures.append(f'{r}:{c} differs in: {", ".join(bad) or "order"}')
        pairs.append(dict(reference=r, candidate=c, packets=[x['packets'], y['packets']],
                          equal=x['sha256'] == y['sha256'], differing_fields=bad))
    return dict(ok=not failures, pairs=pairs, failures=failures)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('reference')
    ap.add_argument('candidate')
    ap.add_argument('--map', required=True)
    ap.add_argument('--receipt')
    a = ap.parse_args()
    mapping = [tuple(int(v) for v in pair.split(':')) for pair in a.map.split(',')]
    r = compare(a.reference, a.candidate, mapping)
    text = json.dumps(r, indent=2)
    if a.receipt:
        pathlib.Path(a.receipt).write_text(text + '\n')
    print(text)
    sys.exit(0 if r['ok'] else 1)
