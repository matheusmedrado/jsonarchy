#!/bin/bash
# Development helper.
#
# Two things defeat the shell's automatic plugin reload while developing
# from a symlinked repo:
#   1. the shell watches ~/.config/omarchy/plugins with inotify, which does
#      not follow symlinks, so edits here are never noticed;
#   2. even after `omarchy-shell shell rescanPlugins`, the QML engine keeps
#      the previously compiled components, so a rescan re-instantiates the
#      old code.
# A shell restart is the only reliable way to pick up new QML. It takes
# about a second and the bar comes straight back.
#
# Usage: ./dev-reload.sh ['{"file": "/path.json"}']
set -euo pipefail
PLUGIN_ID="io.github.matheusmedrado.jsonarchy"
HERE="$(dirname "$(readlink -f "$0")")"

for t in model highlight export read-bounded; do node "$HERE/tests/$t.test.js" >/dev/null; done
omarchy plugin validate "$HERE"
omarchy-restart-shell
for _ in $(seq 1 40); do
  omarchy-shell -q shell ping >/dev/null 2>&1 && break
  sleep 0.25
done
sleep 0.5
if [[ "${1:-}" != "" ]]; then
  omarchy-shell shell summon "$PLUGIN_ID" "$1"
fi
