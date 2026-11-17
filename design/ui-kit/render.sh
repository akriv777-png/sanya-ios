#!/bin/bash
# usage: ./render.sh <name> [height]  -> <name>.png at 2x, width 1600 (height default 2000)
cd "$(dirname "$0")"
n=$1; h=${2:-2000}
google-chrome --headless=new --no-sandbox --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1600,$h --virtual-time-budget=3000 --screenshot="$PWD/$n.png" "file://$PWD/$n.html" 2>/dev/null
