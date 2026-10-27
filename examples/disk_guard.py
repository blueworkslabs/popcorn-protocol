#!/usr/bin/env python3
"""Preflight: will the next stage fit without crossing any free-space floor?

Needs are summed per *filesystem* (st_dev), not per path: two directories on
the same disk share one budget. Optional caps bound how much a directory tree
may hold in total (e.g. cinema scratch on a disk shared with other backups).

Usage:
  disk_guard.py --need /srv/scratch:120 --need /srv/archive:70 \
                --floor /srv/scratch:80 --floor /srv/archive:200 \
                [--cap /srv/backups/cinema-scratch:100:30] [--check-maintenance]

  --need  PATH:GIB          peak additional bytes the stage will write there
  --floor PATH:GIB          free space that must remain on PATH's filesystem
  --cap   DIR:CAP_GIB:ADD   DIR's current size + ADD must stay below CAP
  --check-maintenance       apt auto-upgrade masked and needrestart report-only

Exit 0 and a JSON receipt on pass; exit 1 with reasons on fail.
"""
import argparse, json, os, shutil, subprocess, sys

GIB = 1024 ** 3


def pairs(values, n):
    out = []
    for v in values or []:
        parts = v.rsplit(':', n)
        if len(parts) != n + 1:
            raise SystemExit(f'bad argument {v!r}')
        out.append((parts[0], *[float(x) for x in parts[1:]]))
    return out


def tree_bytes(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
            except FileNotFoundError:
                pass
    return total


def maintenance_failures():
    failures = []
    for unit in ('apt-daily-upgrade.service', 'apt-daily-upgrade.timer'):
        r = subprocess.run(['systemctl', 'is-enabled', unit], capture_output=True, text=True)
        if r.stdout.strip() not in ('masked', 'masked-runtime'):
            failures.append(f'{unit} is {r.stdout.strip() or "unknown"}, expected masked')
    if shutil.which('needrestart'):
        script = ('our %nrconf; do "/etc/needrestart/needrestart.conf";'
                  ' for (sort glob("/etc/needrestart/conf.d/*.conf")) { do $_ }'
                  ' print $nrconf{restart} // "unset";')
        r = subprocess.run(['perl', '-e', script], capture_output=True, text=True)
        if r.stdout.strip() != 'l':
            failures.append(f'needrestart restart mode is {r.stdout.strip()!r}, expected report-only "l"')
    return failures


def check(needs, floors, caps, maintenance):
    failures, per_fs = [], {}
    for path, gib in needs:
        dev = os.stat(path).st_dev
        per_fs.setdefault(dev, {'paths': set(), 'need': 0.0, 'floor': 0.0})
        per_fs[dev]['paths'].add(path)
        per_fs[dev]['need'] += gib
    for path, gib in floors:
        dev = os.stat(path).st_dev
        per_fs.setdefault(dev, {'paths': set(), 'need': 0.0, 'floor': 0.0})
        per_fs[dev]['paths'].add(path)
        per_fs[dev]['floor'] = max(per_fs[dev]['floor'], gib)
    report = []
    for dev, fs in per_fs.items():
        free = shutil.disk_usage(next(iter(fs['paths']))).free / GIB
        left = free - fs['need']
        report.append(dict(paths=sorted(fs['paths']), free_gib=round(free, 1),
                           need_gib=fs['need'], floor_gib=fs['floor'], left_gib=round(left, 1)))
        if left < fs['floor']:
            failures.append(f"{sorted(fs['paths'])}: {free:.1f} GiB free - {fs['need']} needed "
                            f"= {left:.1f} < floor {fs['floor']}")
    for path, cap, add in caps:
        used = tree_bytes(path) / GIB
        report.append(dict(cap_dir=path, used_gib=round(used, 1), add_gib=add, cap_gib=cap))
        if used + add >= cap:
            failures.append(f'{path}: {used:.1f} + {add} GiB >= cap {cap}')
    if maintenance:
        failures += maintenance_failures()
    return dict(ok=not failures, filesystems=report, failures=failures)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--need', action='append')
    ap.add_argument('--floor', action='append')
    ap.add_argument('--cap', action='append')
    ap.add_argument('--check-maintenance', action='store_true')
    a = ap.parse_args()
    r = check(pairs(a.need, 1), pairs(a.floor, 1), pairs(a.cap, 2), a.check_maintenance)
    print(json.dumps(r, indent=2))
    sys.exit(0 if r['ok'] else 1)
