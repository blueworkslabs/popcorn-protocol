#!/usr/bin/env bash
# Self-test for the example scripts on synthetic media. Needs ffmpeg/ffprobe and python3.
# Each script runs on good input (must PASS) and on missing/mutated/invalid input (must FAIL).
# Not covered here: run_stage.sh needs a real systemd host; smoke-test it by hand
# (see README.md). Watcher and maintenance checks run against fake host tools.
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
free=$(python3 -c 'import shutil;print(shutil.disk_usage(".").free/1024**3)')
part=$(python3 -c "print($free*0.6)")   # one part fits, two parts on one filesystem don't
expect pass "small need, small floor"             "$here/disk_guard.py" --need a:0.001 --floor a:0.001
expect pass "one 60% need fits"                   "$here/disk_guard.py" --need a:$part --floor a:0
expect fail "two 60% needs on one fs are summed"  "$here/disk_guard.py" --need a:$part --need b:$part --floor a:0
expect fail "floor above free space"              "$here/disk_guard.py" --need a:0.001 --floor a:1000000
expect fail "need without a floor"                "$here/disk_guard.py" --need a:0.001
expect fail "no checks requested"                 "$here/disk_guard.py"
expect fail "NaN need"                            "$here/disk_guard.py" --need a:nan --floor a:1000000
expect fail "negative need"                       "$here/disk_guard.py" --need a:-1000000 --floor a:1000000
expect fail "missing path"                        "$here/disk_guard.py" --need nope:1 --floor nope:1
expect pass "cap with room"                       "$here/disk_guard.py" --cap capdir:1:0.001
expect fail "cap exceeded"                        "$here/disk_guard.py" --cap capdir:0.0005:0
expect fail "cap on missing dir"                  "$here/disk_guard.py" --cap nope:1:0

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
concurrent_distinct() {
  rm -f cc.json cc.json.lock
  for i in $(seq 20); do echo "{\"id\":\"m$i\"}" > e$i.json; done
  for i in $(seq 20); do "$here/atomic_publish.py" catalog-add cc.json e$i.json >/dev/null & done; wait
  python3 -c 'import json;n=len(json.load(open("cc.json"))["movies"]);print(n);exit(n!=20)'
}
concurrent_same() {
  rm -f cs.json cs.json.lock; ok=0
  for i in $(seq 10); do ("$here/atomic_publish.py" catalog-add cs.json entry.json >/dev/null && touch won.$i) & done; wait
  n=$(ls won.* 2>/dev/null | wc -l); rm -f won.*
  python3 -c "import json;m=len(json.load(open('cs.json'))['movies']);print($n,m);exit(not($n==1 and m==1))"
}
expect pass "20 concurrent adds keep all entries" concurrent_distinct
expect pass "concurrent duplicate: one winner"    concurrent_same

echo "== watcher_check"
# Fake systemctl so live states are testable without real units.
# FAKE_RC!=0 simulates a failed query; a collected unit looks like inactive/success/no invocation.
cat > fake_systemctl <<'SH'
#!/bin/sh
[ "${FAKE_RC:-0}" = 0 ] || exit "$FAKE_RC"
printf 'ActiveState=%s\nResult=%s\nInvocationID=%s\n' "$FAKE_STATE" "${FAKE_RESULT:-success}" "$FAKE_INV"
SH
chmod +x fake_systemctl
w() { # expected_rc receipt state inv progress [result] [query_rc]
  SYSTEMCTL=./fake_systemctl FAKE_STATE=$3 FAKE_INV=$4 FAKE_RESULT=${6:-success} FAKE_RC=${7:-0} \
    "$here/watcher_check.sh" job.service INV-NEW "$2" "$5" 60
  [[ $? == "$1" ]]
}
echo '{"ok": true, "unit": "job.service", "invocation_id": "INV-NEW"}' > ok.json
echo '{"ok": false, "unit": "job.service", "invocation_id": "INV-NEW"}' > bad.json
echo '{"ok": true, "unit": "job.service", "invocation_id": "INV-OLD"}' > old.json
echo '{"ok": true}' > unbound.json
echo '{"ok": true, "unit": "other.service", "invocation_id": "INV-NEW"}' > otherunit.json
echo 'not json' > garbage.json
touch fresh; touch -d '-10 minutes' stale
# receipt cases, unit collected
expect pass "collected + bound ok receipt -> DONE"      w 10 ok.json inactive "" fresh
expect pass "exited success + bound receipt -> DONE"    w 10 ok.json inactive INV-NEW fresh
expect pass "bound failed receipt -> FAILED"            w 11 bad.json inactive "" fresh
expect pass "old invocation receipt -> IDENTITY"        w 12 old.json inactive "" fresh
expect pass "unbound receipt -> IDENTITY"               w 12 unbound.json inactive "" fresh
expect pass "other unit's receipt -> IDENTITY"          w 12 otherunit.json inactive "" fresh
expect pass "unreadable receipt -> IDENTITY"            w 12 garbage.json inactive "" fresh
# live evidence contradicting a bound ok receipt
expect pass "ok receipt + unit failed -> FAILED"        w 11 ok.json failed INV-NEW fresh failed
expect pass "ok receipt + exit-code result -> FAILED"   w 11 ok.json inactive INV-NEW fresh exit-code
expect pass "ok receipt + other live invocation -> IDENTITY" w 12 ok.json active INV-OTHER fresh
expect pass "ok receipt + still running -> BUSY"        w 0 ok.json active INV-NEW stale
expect pass "ok receipt + systemctl error -> UNKNOWN"   w 14 ok.json "" "" fresh success 1
# no receipt
expect pass "running, fresh progress -> BUSY"           w 0 none.json active INV-NEW fresh
expect pass "running, other invocation -> IDENTITY"     w 12 none.json active INV-OTHER fresh
expect pass "running, stale progress -> STALL"          w 13 none.json active INV-NEW stale
expect pass "running, no progress file -> STALL"        w 13 none.json active INV-NEW missing
expect pass "gone without receipt -> FAILED"            w 11 none.json inactive "" fresh
expect pass "failed unit without receipt -> FAILED"     w 11 none.json failed INV-NEW fresh failed

echo "== disk_guard --check-maintenance (fake host tools)"
mkdir -p fakebin
printf '#!/bin/sh\necho "${FAKE_APT:-masked}"\n' > fakebin/systemctl
printf '#!/bin/sh\nexit 0\n' > fakebin/needrestart
printf '#!/bin/sh\necho "${FAKE_NR:-l}"\n' > fakebin/perl
cat > fakebin/snap <<'SH'
#!/bin/sh
case "$1 $FAKE_SNAP" in
  "list none")      echo "No snaps are installed yet." >&2; exit 0 ;;
  "list list-error") echo "error: cannot communicate with server" >&2; exit 1 ;;
  list*)            printf 'Name Version Rev Tracking Publisher Notes\ncore22 1 1 latest/stable canonical base\n' ;;
  "refresh held")   printf 'timer: 00:00~24:00/4\nhold: forever\n' ;;
  "refresh unheld") printf 'timer: 00:00~24:00/4\n' ;;
  "refresh expired") printf 'timer: 00:00~24:00/4\nhold: 2020-01-01T00:00:00Z\n' ;;
  "refresh time-error") exit 1 ;;
esac
SH
chmod +x fakebin/*
m() { PATH="$tmp/fakebin:$PATH" FAKE_SNAP=$1 FAKE_APT=${2:-masked} FAKE_NR=${3:-l} "$here/disk_guard.py" --check-maintenance; }
expect pass "apt masked, report-only, snap held"   m held
expect pass "no snaps installed"                   m none
expect fail "snaps installed, no hold"             m unheld
expect fail "dated hold instead of forever"        m expired
expect fail "snap list fails"                      m list-error
expect fail "snap refresh --time fails"            m time-error
expect fail "apt upgrade not masked"               m held enabled
expect fail "needrestart restarts automatically"   m held masked a

echo "== kodi_scan_if_idle (fake Kodi)"
cat > fake_kodi.py <<'PY'
import json, socket, sys, time
mode = sys.argv[2]
movie = 'smb://media/Movies/Example (2020)/Example (2020).mkv'
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 0)); s.listen(1)
open(sys.argv[1], 'w').write(str(s.getsockname()[1]))
c, _ = s.accept(); dec = json.JSONDecoder(); buf = ''; scanned = False; polls = 0
def send(obj):
    data = json.dumps(obj, ensure_ascii=False).encode()
    cut = data.find('ä'.encode()) + 1          # inside the 2-byte UTF-8 sequence
    if mode == 'split' and cut > 0:            # two writes with a pause: two client reads
        c.sendall(data[:cut]); time.sleep(0.3); c.sendall(data[cut:])
    else: c.sendall(data)
while True:
    data = c.recv(65536)
    if not data: break
    buf += data.decode()
    while buf.strip():
        try: req, end = dec.raw_decode(buf.lstrip())
        except json.JSONDecodeError: break
        buf = buf.lstrip()[end:]; m = req['method']
        if m == 'Player.GetActivePlayers':
            polls += 1
            if mode == 'playing': res = [{'playerid': 1, 'type': 'video'}]
            elif mode == 'null' or (mode == 'null-after' and polls > 1): res = None
            else: res = []
        elif m == 'VideoLibrary.Scan':
            scanned = True; res = 'OK'; open('scanned', 'w').close()
        elif m == 'VideoLibrary.GetMovies':
            res = {'movies': [{'movieid': 1, 'file': movie, 'label': 'Exämple – Ünïcode'}] if scanned else []}
        else: res = None
        send({'jsonrpc': '2.0', 'id': req['id'], 'result': res})
        if m == 'VideoLibrary.Scan':
            send({'jsonrpc': '2.0', 'method': 'VideoLibrary.OnScanFinished', 'params': {}})
PY
kodi_case() { # mode expect_file
  rm -f port scanned; python3 fake_kodi.py port "$1" &
  for _ in $(seq 50); do [[ -s port ]] && break; sleep 0.1; done
  "$here/kodi_scan_if_idle.py" --port "$(cat port)" --timeout 10 --directory smb://media/Movies/ --expect-file "$2"
  local rc=$?; wait; return $rc
}
no_scan() { kodi_case "$@"; local rc=$?; [[ ! -e scanned ]] || { echo "scan was triggered"; return 0; }; return $rc; }
movie='smb://media/Movies/Example (2020)/Example (2020).mkv'
expect pass "idle -> scan and find entry"         kodi_case idle "$movie"
expect pass "multibyte title split across reads"  kodi_case split "$movie"
expect fail "playing -> refuses, no scan"         no_scan playing "$movie"
expect fail "null player state -> refuses, no scan" no_scan null "$movie"
expect fail "null state after scan -> not ok"     kodi_case null-after "$movie"
expect fail "entry not found after scan"          kodi_case idle "smb://media/Movies/Missing.mkv"

echo
echo "selftest: $pass passed, $fail failed"
[[ $fail == 0 ]]
