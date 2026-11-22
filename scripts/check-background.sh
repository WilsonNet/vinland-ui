#!/usr/bin/env sh
# Verifies the background-input guarantee on a real X11 window:
#   - VUI_BACKGROUND=1 maps a visible, non-focusable window (not the active one)
#   - vui-ctl pointer commands do not move the OS pointer
#   - vui-ctl info reports the background/focus state
#   - foreground/background are an explicit, reversible escape hatch
#
# Runs under Xvfb with SDL forced to X11. Never on the user's desktop: it
# unsets WAYLAND_DISPLAY so SDL cannot connect to the live compositor, which is
# the failure mode this script exists to prevent. Exits 77 when the display
# tooling is unavailable so a test runner can skip it.
set -eu
cd "$(dirname "$0")/.."

[ -x build/showroom ] && [ -x build/vui-ctl ] || {
	echo "check-background: run ./build.sh first" >&2
	exit 1
}
for tool in Xvfb xdotool xprop openbox; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "check-background: $tool not installed; skipping"
		exit 77
	}
done

xvfb-run -a -s "-screen 0 1280x800x24" sh -s <<'INNER'
set -eu
# Critical: xvfb-run does not clear the parent's Wayland socket, and SDL would
# prefer Wayland over the sandboxed X server, mapping a window on the user's
# real desktop. Force X11 for the whole check.
unset WAYLAND_DISPLAY
export SDL_VIDEO_DRIVER=x11
openbox >/tmp/vui-background-wm.log 2>&1 &
WM=$!
sleep 1
PORT=7498
VUI_BACKEND=gl VUI_BACKGROUND=1 VUI_PORT=$PORT VUI_SIZE=900x600 \
	./build/showroom >/tmp/vui-background-app.log 2>&1 &
APP=$!
trap 'kill $APP $WM 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 80); do
	./build/vui-ctl --port $PORT ping >/dev/null 2>&1 && break
	sleep 0.2
done
./build/vui-ctl --port $PORT ping >/dev/null
sleep 0.5

WID=$(xdotool search --pid $APP 2>/dev/null | head -1)
[ -n "$WID" ] || {
	echo "FAIL: background window was not mapped"
	exit 1
}
active=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | sed 's/.*# //')
[ "$active" != "$WID" ] || {
	echo "FAIL: background window stole focus (active=$active)"
	exit 1
}

xdotool mousemove 640 400
sleep 0.2
before=$(xdotool getmouselocation)
info=$(./build/vui-ctl --port $PORT info)
case "$info" in
	*'"background":true'*) ;;
	*) echo "FAIL: background not reported: $info"; exit 1 ;;
esac
case "$info" in
	*'"focusable":false'*) ;;
	*) echo "FAIL: window reports focusable: $info"; exit 1 ;;
esac

./build/vui-ctl --port $PORT click-text "Introduction" >/dev/null
sleep 0.3
after=$(xdotool getmouselocation)
[ "$before" = "$after" ] || {
	echo "FAIL: synthetic click moved the pointer: $before -> $after"
	exit 1
}
./build/vui-ctl --port $PORT screenshot /tmp/vui-background.png >/dev/null

fg=$(./build/vui-ctl --port $PORT foreground)
case "$fg" in
	*'"ok":true'*) ;;
	*) echo "FAIL: foreground escape hatch failed: $fg"; exit 1 ;;
esac
bg=$(./build/vui-ctl --port $PORT background)
case "$bg" in
	*'"ok":true'*'"background":true'*) ;;
	*) echo "FAIL: background toggle failed: $bg"; exit 1 ;;
esac
./build/vui-ctl --port $PORT release >/dev/null
./build/vui-ctl --port $PORT quit >/dev/null 2>&1 || true
echo "check-background: ok (mapped=$WID, pointer stayed at $before, screenshot /tmp/vui-background.png)"
INNER
