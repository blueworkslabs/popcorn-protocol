#!/usr/bin/env python3
"""Publish an accepted file into a library: copy, read back, verify, no-replace.

  publish SOURCE DEST_PATH [--sha256 EXPECTED]
      1. hash SOURCE (or trust --sha256 from an earlier receipt and re-check it),
      2. copy into a hidden staging file in DEST's directory (same filesystem),
         fsync,
      3. read the staged copy back from disk and hash it independently,
      4. chmod 0444 and hard-link to DEST: fails if DEST exists (no-replace),
      5. remove the staging name.

  catalog-add CATALOG.json ENTRY.json
      Add one entry (must have a unique "id") to {"movies": [...]}, refusing a
      duplicate id, then atomically replace the catalog (temp + fsync + rename).
      Always edits the *current* catalog; never write back an old snapshot.

Prints a JSON receipt. Exit 1 on any mismatch or conflict.
"""
import hashlib, json, os, pathlib, shutil, sys, tempfile

CHUNK = 8 * 1024 * 1024


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        while b := f.read(CHUNK):
            h.update(b)
    return h.hexdigest()


def drop_cache(path):
    # Best effort: make the readback come from disk, not the page cache.
    try:
        fd = os.open(path, os.O_RDONLY)
        os.fsync(fd)
        os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
        os.close(fd)
    except OSError:
        pass


def publish(source, dest, expected=None):
    source, dest = pathlib.Path(source), pathlib.Path(dest)
    if dest.exists():
        raise FileExistsError(f'{dest} already exists; publication never replaces')
    src_hash = sha256(source)
    if expected and src_hash != expected:
        raise ValueError(f'source hash {src_hash} != expected {expected}')
    fd, staging = tempfile.mkstemp(prefix='.staging-', dir=dest.parent)
    try:
        with os.fdopen(fd, 'wb') as out, open(source, 'rb') as inp:
            shutil.copyfileobj(inp, out, CHUNK)
            out.flush()
            os.fsync(out.fileno())
        drop_cache(staging)
        readback = sha256(staging)
        if readback != src_hash:
            raise ValueError(f'readback {readback} != source {src_hash}')
        os.chmod(staging, 0o444)
        os.link(staging, dest)          # atomic, raises FileExistsError on a race
        dir_fd = os.open(dest.parent, os.O_RDONLY)
        os.fsync(dir_fd)
        os.close(dir_fd)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)
    return dict(ok=True, published=str(dest), bytes=dest.stat().st_size, sha256=src_hash,
                readback_sha256=readback, mode=oct(dest.stat().st_mode & 0o777))


def catalog_add(catalog, entry_path):
    catalog = pathlib.Path(catalog)
    entry = json.loads(pathlib.Path(entry_path).read_text())
    current = json.loads(catalog.read_text()) if catalog.exists() else {'movies': []}
    if not entry.get('id'):
        raise ValueError('entry needs an id')
    if any(m.get('id') == entry['id'] for m in current['movies']):
        raise FileExistsError(f"id {entry['id']!r} already in catalog")
    current['movies'].append(entry)
    fd, tmp = tempfile.mkstemp(prefix='.catalog-', dir=catalog.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(current, f, indent=2)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, 0o644)
        os.replace(tmp, catalog)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return dict(ok=True, catalog=str(catalog), entries=len(current['movies']), added=entry['id'])


if __name__ == '__main__':
    try:
        if len(sys.argv) >= 4 and sys.argv[1] == 'publish':
            exp = sys.argv[sys.argv.index('--sha256') + 1] if '--sha256' in sys.argv else None
            r = publish(sys.argv[2], sys.argv[3], exp)
        elif len(sys.argv) == 4 and sys.argv[1] == 'catalog-add':
            r = catalog_add(sys.argv[2], sys.argv[3])
        else:
            raise SystemExit(__doc__)
    except (OSError, ValueError) as e:
        print(json.dumps(dict(ok=False, error=f'{type(e).__name__}: {e}')))
        sys.exit(1)
    print(json.dumps(r, indent=2))
