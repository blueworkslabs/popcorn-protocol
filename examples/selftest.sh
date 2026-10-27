#!/usr/bin/env bash
# Self-test for the example scripts on synthetic media. Needs ffmpeg/ffprobe and python3.
# Every check runs on good input (must PASS) and on missing/mutated input (must FAIL).
# Uses a private temp dir and removes it on exit. Touches nothing else.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/popcorn-selftest.XXXXXX")
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT
cd "$tmp"
pass=0; fail=0
expect() { # expect pass|fail "label" cmd...
  local want=$1 label=$2; shift 2
  if "$@" >"$tmp/last.log" 2>&1; then got=pass; else got=fail; fi
  if [[ $got == "$want" ]]; then pass=$((pass+1)); echo "ok   $label ($got as expected)"
  else fail=$((fail+1)); echo "FAIL $label (wanted $want, got $got)"; sed 's/^/     /' "$tmp/last.log" | head -15; fi
}

ff() { ffmpeg -nostdin -hide_banner -v error -y "$@"; }
# 48 frames at 24000/1001, two audio tracks (EN AC-3 5.1, DE AAC stereo), Matroska.
ff -f lavfi -i testsrc2=size=320x180:rate=24000/1001 -f lavfi -i sine=f=440:r=48000 \
   -f lavfi -i sine=f=660:r=48000 -frames:v 48 -t 2.002 \
   -map 0:v -map 1:a -map 2:a -c:v libx264 -preset ultrafast -bf 0 \
   -c:a:0 ac3 -ac:a:0 6 -c:a:1 aac -ac:a:1 2 ref.mkv || { echo "cannot build fixture"; exit 1; }
ff -i ref.mkv -map 0 -c copy -copyts copy.mkv                  # faithful remux
ff -i ref.mkv -map 0 -c copy normalized.mkv                    # default remux: ffmpeg shifts timestamps
ff -i ref.mkv -map 0:v -map 0:a:0 -c copy drop_audio.mkv       # omission: one track gone
ff -i ref.mkv -map 0 -c copy -c:a:1 aac -b:a:1 64k reenc.mkv   # mutation: payload changed
ff -i ref.mkv -map 0 -c copy -output_ts_offset 0.5 shifted.mkv # mutation: timestamps moved
head -c $(( $(stat -c %s ref.mkv) * 2 / 3 )) ref.mkv > truncated.mkv

echo "== decode_verify"
expect pass "full decode, exact frames"           "$here/decode_verify.py" ref.mkv --frames 48 --audio-streams 2
expect fail "wrong expected frame count"          "$here/decode_verify.py" ref.mkv --frames 47 --audio-streams 2
expect fail "missing audio stream"                "$here/decode_verify.py" drop_audio.mkv --frames 48 --audio-streams 2
expect fail "truncated file"                      "$here/decode_verify.py" truncated.mkv --frames 48 --audio-streams 2

echo "== packet_compare"
expect pass "faithful remux"                      "$here/packet_compare.py" ref.mkv copy.mkv --map 1:1,2:2
expect fail "default ffmpeg remux shifts timestamps" "$here/packet_compare.py" ref.mkv normalized.mkv --map 1:1,2:2
expect fail "candidate missing a stream"          "$here/packet_compare.py" ref.mkv drop_audio.mkv --map 1:1,2:2
expect fail "re-encoded payload"                  "$here/packet_compare.py" ref.mkv reenc.mkv --map 1:1,2:2
expect fail "shifted timestamps"                  "$here/packet_compare.py" ref.mkv shifted.mkv --map 1:1,2:2

echo "== disk_guard"
mkdir -p a b capdir; head -c 1048576 /dev/zero > capdir/blob
expect pass "small need, small floor"             "$here/disk_guard.py" --need a:0.001 --floor a:0.001
expect fail "floor above free space"              "$here/disk_guard.py" --need a:0.001 --floor a:1000000
expect fail "same filesystem needs are summed"    "$here/disk_guard.py" --need a:600000 --need b:600000 --floor a:0 \
                                                    --floor b:0
expect fail "cap exceeded"                        "$here/disk_guard.py" --cap capdir:0.0005:0

echo "== atomic_publish"
mkdir -p lib
expect pass "publish with readback"               "$here/atomic_publish.py" publish ref.mkv lib/Example.mkv
expect fail "never replaces an existing file"     "$here/atomic_publish.py" publish copy.mkv lib/Example.mkv
expect fail "wrong expected source hash"          "$here/atomic_publish.py" publish ref.mkv lib/Other.mkv --sha256 00
expect pass "published file identical, read-only" bash -c 'cmp ref.mkv lib/Example.mkv && [[ $(stat -c %a lib/Example.mkv) == 444 ]] \
                                                    && ! ls lib/.staging-* 2>/dev/null'
echo '{"id":"example","title":"Example"}' > entry.json
expect pass "catalog add"                         "$here/atomic_publish.py" catalog-add catalog.json entry.json
expect fail "catalog duplicate id"                "$here/atomic_publish.py" catalog-add catalog.json entry.json

echo "== watcher_check"
echo '{"ok": true}' > ok.json; echo '{"ok": false}' > bad.json; touch progress
expect pass "ok receipt -> DONE"                  bash -c "\"$here/watcher_check.sh\" none-unit x ok.json progress 60; [[ \$? == 10 ]]"
expect pass "failed receipt -> FAILED"            bash -c "\"$here/watcher_check.sh\" none-unit x bad.json progress 60; [[ \$? == 11 ]]"
expect pass "no receipt, unit gone -> FAILED"     bash -c "\"$here/watcher_check.sh\" popcorn-selftest-nonexistent x missing.json progress 60; [[ \$? == 11 ]]"

echo "== kodi_scan_if_idle (fake Kodi)"
cat > fake_kodi.py <<'PY'
import json, socket, sys
playing = sys.argv[2] == 'playing'
movie = 'smb://media/Movies/Example (2020)/Example (2020).mkv'
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 0)); s.listen(1)
open(sys.argv[1], 'w').write(str(s.getsockname()[1]))
c, _ = s.accept(); dec = json.JSONDecoder(); buf = ''; scanned = False
while True:
    data = c.recv(65536)
    if not data: break
    buf += data.decode()
    while buf.strip():
        try: req, end = dec.raw_decode(buf.lstrip())
        except json.JSONDecodeError: break
        buf = buf.lstrip()[end:]; m = req['method']
        if m == 'Player.GetActivePlayers': res = [{'playerid': 1, 'type': 'video'}] if playing else []
        elif m == 'VideoLibrary.Scan': scanned = True; res = 'OK'
        elif m == 'VideoLibrary.GetMovies':
            res = {'movies': [{'movieid': 1, 'file': movie, 'label': 'Example'}] if scanned else []}
        else: res = None
        c.sendall(json.dumps({'jsonrpc': '2.0', 'id': req['id'], 'result': res}).encode())
        if m == 'VideoLibrary.Scan':
            c.sendall(json.dumps({'jsonrpc': '2.0', 'method': 'VideoLibrary.OnScanFinished', 'params': {}}).encode())
PY
kodi_case() { # mode expect_file
  rm -f port; python3 fake_kodi.py port "$1" &
  for _ in $(seq 50); do [[ -s port ]] && break; sleep 0.1; done
  "$here/kodi_scan_if_idle.py" --port "$(cat port)" --timeout 10 --directory smb://media/Movies/ --expect-file "$2"
  local rc=$?; wait; return $rc
}
movie='smb://media/Movies/Example (2020)/Example (2020).mkv'
expect pass "idle -> scan and find entry"         kodi_case idle "$movie"
expect fail "playing -> refuses to scan"          kodi_case playing "$movie"
expect fail "entry not found after scan"          kodi_case idle "smb://media/Movies/Missing.mkv"

echo
echo "selftest: $pass passed, $fail failed"
[[ $fail == 0 ]]
