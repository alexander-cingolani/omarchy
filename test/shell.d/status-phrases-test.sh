#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The panels read the same per-widget setting, defaulting to phrases on.
for panel in power bluetooth network; do
  if ! rg -q 'readonly property bool statusPhrases: setting\("statusPhrases", true\) !== false' "$ROOT/shell/plugins/panels/$panel/Panel.qml"; then
    fail "$panel panel reads the statusPhrases setting"
  fi
done
pass "power, bluetooth and network read the statusPhrases setting"

if ! rg -q 'if \(!statusPhrases \|\| fullyCharged\) return \[\]' "$ROOT/shell/plugins/panels/power/Panel.qml"; then
  fail "power drops its phrases when statusPhrases is off"
fi
if ! rg -q 'rotatingPhrases: statusPhrases && adapter && adapter\.enabled' "$ROOT/shell/plugins/panels/bluetooth/Panel.qml"; then
  fail "bluetooth stops rotating when statusPhrases is off"
fi
if ! rg -q 'running: root\.opened && root\.statusPhrases &&' "$ROOT/shell/plugins/panels/network/Panel.qml"; then
  fail "network stops rotating when statusPhrases is off"
fi
pass "each panel stops rotating its phrases when statusPhrases is off"

# The command drives omarchy-bar against stubs: three widgets, state in a file.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat >"$tmp/bin/omarchy-bar" <<'STUB'
#!/bin/bash
state="$STUB_DIR/$2.$3"
case $1 in
get) [[ -f $state ]] && cat "$state" || exit 1 ;;
set) [[ $2 == "omarchy.network" && -n ${STUB_NO_NETWORK:-} ]] && exit 1; echo "$4" >"$state" ;;
esac
STUB
printf '#!/bin/bash\necho "$*" >>"$STUB_DIR/notifications"\n' >"$tmp/bin/omarchy-notification-send"
printf '#!/bin/bash\necho "$1"\n' >"$tmp/bin/omarchy-i18n"
chmod +x "$tmp/bin/"*

status() { PATH="$tmp/bin:$PATH" STUB_DIR=$tmp "$ROOT/bin/omarchy-toggle-status-phrases" --status; }
run() { PATH="$tmp/bin:$PATH" STUB_DIR=$tmp "$ROOT/bin/omarchy-toggle-status-phrases" "$@"; }

[[ $(status) == "on" ]] || fail "status phrases default to on"
run toggle
[[ $(status) == "off" ]] || fail "toggle turns status phrases off"
for widget in power bluetooth network; do
  [[ $(<"$tmp/omarchy.$widget.statusPhrases") == "false" ]] || fail "toggle off sets $widget"
done
run toggle
[[ $(status) == "on" ]] || fail "toggle turns status phrases back on"
run off
[[ $(status) == "off" ]] || fail "off turns status phrases off"
run on
[[ $(status) == "on" ]] || fail "on turns status phrases on"
pass "omarchy-toggle-status-phrases sets every panel and reports the state"

STUB_NO_NETWORK=1 run off
[[ $(status) == "off" ]] || fail "a widget missing from the bar does not block the toggle"
pass "omarchy-toggle-status-phrases tolerates widgets that are not on the bar"

if run sideways 2>/dev/null; then
  fail "omarchy-toggle-status-phrases rejects unknown arguments"
fi
pass "omarchy-toggle-status-phrases rejects unknown arguments"
