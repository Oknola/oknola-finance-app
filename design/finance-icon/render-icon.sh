#!/bin/bash
# Renders the Finance icon, its full-bleed variant and the mark to PNG with headless Chrome or Chromium
# (SVG lighting filters need a browser). Usage: render-icon.sh <folder holding the three SVGs>
# CHROME picks the browser binary (default: chromium; on GitHub's Ubuntu runners use google-chrome).
set -euo pipefail
cd "$1"
chrome="${CHROME:-chromium}"
render() { # svg size out.png
  printf '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}img{display:block;width:%spx;height:%spx}</style><img src="%s">\n' "$2" "$2" "$1" > .render.html
  "$chrome" --headless=new --no-sandbox --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size="$2,$2" --force-device-scale-factor=1 --screenshot="$PWD/$3" "file://$PWD/.render.html"
}
render finance-icon.svg 1024 finance-icon-1024.png
render finance-icon-full-bleed.svg 1024 finance-icon-full-bleed-1024.png
render finance-mark.svg 512 finance-mark-512.png
rm -f .render.html
