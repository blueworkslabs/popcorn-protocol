#!/usr/bin/env python3
"""Add new media to a Kodi library only while nothing is playing.

Talks JSON-RPC over Kodi's raw TCP socket (default 127.0.0.1:9090; keep it
loopback-only and tunnel over SSH if needed).

  1. Player.GetActivePlayers must be []      -> otherwise exit 3, change nothing
  2. VideoLibrary.Scan(directory, showdialogs=false)
  3. wait for the VideoLibrary.OnScanFinished notification (bounded)
  4. VideoLibrary.GetMovies filtered by --expect-file must find the entry
  5. Player.GetActivePlayers must still be []

Never plays, seeks, mutes, navigates or restarts anything.

Usage: kodi_scan_if_idle.py --directory smb://media-host/Movies/ \
         --expect-file "smb://media-host/Movies/Example (2020)/Example (2020).mkv" \
         [--host 127.0.0.1 --port 9090 --timeout 600]
"""
import argparse, json, socket, sys, time


class Kodi:
    def __init__(self, host, port, timeout):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.buf, self.next_id, self.events = '', 1, []
        self.decoder = json.JSONDecoder()

    def _read_object(self):
        while True:
            stripped = self.buf.lstrip()
            if stripped:
                try:
                    obj, end = self.decoder.raw_decode(stripped)
                    self.buf = stripped[end:]
                    return obj
                except json.JSONDecodeError:
                    pass
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError('Kodi closed the connection')
            self.buf += chunk.decode()

    def call(self, method, **params):
        rid = self.next_id
        self.next_id += 1
        self.sock.sendall(json.dumps(dict(jsonrpc='2.0', id=rid, method=method, params=params)).encode())
        while True:
            obj = self._read_object()
            if obj.get('id') == rid:
                if 'error' in obj:
                    raise RuntimeError(f'{method}: {obj["error"]}')
                return obj['result']
            if 'method' in obj:          # notification arriving in between
                self.events.append(obj['method'])

    def wait_event(self, name, deadline):
        while name not in self.events:
            if time.monotonic() > deadline:
                raise TimeoutError(f'no {name} before deadline')
            obj = self._read_object()
            if 'method' in obj:
                self.events.append(obj['method'])


def main(a):
    k = Kodi(a.host, a.port, a.timeout)
    before = k.call('Player.GetActivePlayers')
    if before:
        print(json.dumps(dict(ok=False, skipped=True, reason='playback active', players=before)))
        return 3
    deadline = time.monotonic() + a.timeout
    k.call('VideoLibrary.Scan', directory=a.directory, showdialogs=False)
    k.wait_event('VideoLibrary.OnScanFinished', deadline)
    movies = k.call('VideoLibrary.GetMovies', properties=['file', 'title', 'year', 'art'])
    found = [m for m in movies.get('movies', []) if m.get('file') == a.expect_file]
    after = k.call('Player.GetActivePlayers')
    ok = len(found) == 1 and not after
    print(json.dumps(dict(ok=ok, found=found, players_after=after), indent=2))
    return 0 if ok else 1


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--directory', required=True)
    ap.add_argument('--expect-file', required=True)
    ap.add_argument('--host', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=9090)
    ap.add_argument('--timeout', type=float, default=600)
    sys.exit(main(ap.parse_args()))
