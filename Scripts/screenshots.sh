#!/usr/bin/env bash
# Gera os prints do README com dados fictícios: Scripts/screenshots.sh → docs/images/*.png
# Usa o modo demonstração (--demo --snapshot): nada aparece na tela e os dados reais não são tocados.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RAW="$ROOT/build/screenshots"
mkdir -p "$RAW" "$ROOT/docs/images"

"$ROOT/Scripts/build.sh" release >/dev/null
"$ROOT/build/Rastro.app/Contents/MacOS/Rastro" --demo --snapshot "$RAW" &
pid=$!
for _ in $(seq 1 60); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
kill -0 "$pid" 2>/dev/null && { kill "$pid"; echo "o app não terminou a tempo" >&2; exit 1; }

for screen in timeline stats deploy standup; do
  xcrun swift "$ROOT/Scripts/frame-screenshot.swift" "$RAW/$screen.png" "$ROOT/docs/images/$screen.png"
  echo "✓ docs/images/$screen.png"
done
