#!/usr/bin/env bash
# Full cc-OS test suite: lint, installer, kernel, and every bundled app.
# Run from the tools/ directory.
set -u
cd "$(dirname "$0")"

fail=0
run() {
  local label="$1"; shift
  local out
  if out=$(node run.mjs "$@" 2>&1); then
    echo "  PASS  $label"
  else
    echo "  FAIL  $label"
    echo "$out" | sed 's/^/        /' | tail -20
    fail=1
  fi
}

echo "== single-file bundle =="
if python build_bundle.py > out/bundle.txt 2>&1; then
  echo "  PASS  $(tail -1 out/bundle.txt)"
else
  echo "  FAIL  building install.lua"
  sed 's/^/        /' out/bundle.txt
  fail=1
fi
run "installer unpacks and boots" tests/t_install.lua

echo "== every app module loads =="
run "module registry" tests/t_load.lua

echo "== kernel =="
run "start menu, drag, minimize, close" tests/t_boot.lua
run "icons, maximize, resize, crash dialog, context menus, alt-tab" tests/t_wm2.lua
run "resizing reflows app content" tests/t_resize.lua
run "session persists and restores across boots" tests/t_session.lua

echo "== apps =="
run "editor, files, calculator, terminal, snake, settings" tests/t_apps.lua
run "chat + file share over the modem" tests/t_net.lua
run "alarms + notes" tests/t_clock_notes.lua

echo "== pixel-art icons + boot splash =="
run "every app icon renders" tests/t_icons.lua
run "calculator icon (regression: cell-alignment bug)" tests/t_icon_calc.lua
run "boot splash wordmark" tests/t_splash.lua
run "desktop + Start menu + taskbar visual smoke test" tests/t_visual.lua

echo "== nitpick QA pass =="
run "piano: all 25 keys fit and are clickable (regression)" tests/t_qa_piano.lua
run "files: delete requires Y/N confirmation" tests/t_qa_files_delete.lua
run "context menu: right-click elsewhere reopens in one click" tests/t_qa_ctxmenu.lua

echo
if [ "$fail" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED"
fi
exit $fail
