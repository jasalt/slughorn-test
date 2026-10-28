#!/bin/sh
# Headless evaluation of the web build: serves the page over HTTP, opens it with
# ?selftest in headless Chromium (WebGL2 via SwiftShader) and checks the DOM verdict.
#
# Usage: smoke.sh <web source dir> <vector-feedback.wasm> [screenshot.png]
set -eu

src=$1
wasm=$2
shot=${3:-}
browser=${CHROMIUM:-$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)}
[ -n "$browser" ] || { echo "smoke.sh: no Chromium found (set CHROMIUM)" >&2; exit 1; }

root=$(mktemp -d)
trap 'kill "$server" 2>/dev/null || true; rm -rf "$root" 2>/dev/null || true' EXIT INT TERM
cp "$src"/index.html "$src"/vector-feedback.js "$wasm" "$root"/
port=$((20000 + $$ % 20000))
python3 -I -m http.server --bind 127.0.0.1 --directory "$root" "$port" >/dev/null 2>&1 &
server=$!
i=0
until python3 -I -c "import socket,sys; socket.create_connection(('127.0.0.1', $port), 1)" 2>/dev/null; do
	i=$((i + 1)); [ "$i" -lt 50 ] || { echo "smoke.sh: server did not start" >&2; exit 1; }
	sleep 0.1
done

devtools=$((port + 1))
url="http://127.0.0.1:$port/index.html?selftest=${SELFTEST_FRAMES:-120}"
"$browser" --headless=new --no-first-run --no-default-browser-check --disable-extensions \
	--use-angle=swiftshader --enable-unsafe-swiftshader --ignore-gpu-blocklist \
	--window-size=1280,800 --user-data-dir="$root/profile" \
	--remote-debugging-address=127.0.0.1 --remote-debugging-port="$devtools" \
	"$url" >"$root/chromium.log" 2>&1 &
chrome=$!
cleanup() {
	rc=$?
	kill "$server" "$chrome" 2>/dev/null || true
	wait "$chrome" 2>/dev/null || true
	rm -rf "$root" 2>/dev/null || true
	exit "$rc"
}
trap cleanup EXIT INT TERM

if python3 -I "$(dirname "$0")/cdp_selftest.py" "$devtools" "${SELFTEST_TIMEOUT:-300}" "http://127.0.0.1:$port/index.html" $shot; then
	echo "web selftest: PASS"
	exit 0
fi
echo "web selftest: FAIL" >&2
tail -n 20 "$root/chromium.log" >&2
exit 1
