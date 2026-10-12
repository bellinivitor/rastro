#!/usr/bin/env bash
# Fecha o Dev Timeline e espera ele sair de fato antes de um novo `open`.
pkill -x DevTimeline 2>/dev/null || exit 0
for _ in $(seq 1 50); do
  pgrep -x DevTimeline >/dev/null || exit 0
  sleep 0.1
done
pkill -9 -x DevTimeline 2>/dev/null || true
