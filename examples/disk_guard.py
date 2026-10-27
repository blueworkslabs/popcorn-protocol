#!/usr/bin/env python3
"""Preflight: will the next stage fit without crossing any free-space floor?

Needs are summed per *filesystem* (st_dev), not per path: two directories on
the same disk share one budget. Optional caps bound how much a directory tree
may hold in total (e.g. cinema scratch on a disk shared with other backups).

Fails closed: no checks requested, a non-finite or negative number, a missing
path, a filesystem that receives writes without a floor, or an unreadable cap
tree are all failures, never an empty pass.

Usage:
  disk_guard.py --need /srv/scratch:120 --need /srv/archive:70 \
                --floor /srv/scratch:80 --floor /srv/archive:200 \
                [--cap /srv/backups/cinema-scratch:100:30] [--check-maintenance]

  --need  PATH:GIB          peak additional bytes the stage will write there
  --floor PATH:GIB          free space that must remain on PATH's filesystem
  --cap   DIR:CAP_GIB:ADD   DIR's current size + ADD must stay below CAP;
                            DIR must already exist (cap the parent of a new stage)
  --check-maintenance       apt auto-upgrade masked, needrestart report-only,
                            snap refreshes held (if snaps are installed)

Exit 0 and a JSON receipt on pass; exit 1 with reasons on fail.
Free space is a snapshot: other writers can still consume it after this check.
"""
import argparse, json, math, os, shutil, subprocess, sys

GIB = 1024 ** 3


class Bad(Exception):
    pass


def parse(values, n):
    out = []
    for v in values or []:
        parts = v.rsplit(':', n)
        if len(parts) != n + 1 or not parts[0]:
            raise Bad(f'bad argument {v!r}')
        try:
            nums = [float(x) for x in parts[1:]]
        except ValueError:
            raise Bad(f'bad number in {v!r}')
        if not all(math.isfinite(x) and x >= 0 for x in nums):
            raise Bad(f'numbers must be finite and non-negative: {v!r}')
        if not os.path.exists(parts[0]):
            raise Bad(f'path does not exist: {parts[0]}')
        out.append((parts[0], *nums))
    return out


def tree_bytes(path):
    if not os.path.isdir(path):
        raise Bad(f'cap target is not a directory: {path}')

    def boom(err):
        raise Bad(f'cannot read cap tree: {err}')

    total = 0
    for root, _, files in os.walk(path, onerror=boom):
        for f in files:
            total += os.lstat(os.path.join(root, f)).st_size
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
    if shutil.which('snap'):
        listed = subprocess.run(['snap', 'list'], capture_output=True, text=True)
        if listed.returncode != 0:
            failures.append(f'snap list failed (rc {listed.returncode}): cannot tell whether snaps auto-refresh')
        elif len(listed.stdout.strip().splitlines()) > 1:    # header + at least one snap
            t = subprocess.run(['snap', 'refresh', '--time'], capture_output=True, text=True)
            holds = [line.split(':', 1)[1].strip() for line in t.stdout.splitlines() if line.startswith('hold:')]
            if t.returncode != 0:
                failures.append(f'snap refresh --time failed (rc {t.returncode})')
            elif holds != ['forever']:
                # Manual-install policy wants an indefinite hold (snap refresh --hold);
                # a dated hold expires and refreshes resume on their own.
                failures.append(f'snap refresh hold is {holds or "absent"}, expected ["forever"]')
    return failures


def check(needs, floors, caps, maintenance):
    if not (needs or floors or caps or maintenance):
        raise Bad('no checks requested')
    failures, per_fs = [], {}

    def fs(path):
        dev = os.stat(path).st_dev
        return per_fs.setdefault(dev, {'paths': set(), 'need': 0.0, 'floor': None})

    for path, gib in needs:
        entry = fs(path)
        entry['paths'].add(path)
        entry['need'] += gib
    for path, gib in floors:
        entry = fs(path)
        entry['paths'].add(path)
        entry['floor'] = max(entry['floor'] or 0.0, gib)
    report = []
    for entry in per_fs.values():
        paths = sorted(entry['paths'])
        if entry['floor'] is None:
            failures.append(f'{paths}: receives writes but has no --floor')
            continue
        free = shutil.disk_usage(paths[0]).free / GIB
        left = free - entry['need']
        report.append(dict(paths=paths, free_gib=round(free, 1), need_gib=entry['need'],
                           floor_gib=entry['floor'], left_gib=round(left, 1)))
        if left < entry['floor']:
            failures.append(f"{paths}: {free:.1f} GiB free - {entry['need']} needed "
                            f"= {left:.1f} < floor {entry['floor']}")
    for path, cap, add in caps:
        used = tree_bytes(path) / GIB
        report.append(dict(cap_dir=path, used_gib=round(used, 3), add_gib=add, cap_gib=cap))
        if used + add >= cap:
            failures.append(f'{path}: {used:.3f} + {add} GiB >= cap {cap}')
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
    try:
        r = check(parse(a.need, 1), parse(a.floor, 1), parse(a.cap, 2), a.check_maintenance)
    except (Bad, OSError) as e:
        r = dict(ok=False, failures=[str(e)])
    print(json.dumps(r, indent=2))
    sys.exit(0 if r['ok'] else 1)
