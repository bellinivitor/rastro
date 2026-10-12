#!/usr/bin/env bash
# Fecha o Rastro e espera ele sair de fato antes de um novo `open`.
pkill -x Rastro 2>/dev/null || exit 0
for _ in $(seq 1 50); do
  pgrep -x Rastro >/dev/null || exit 0
  sleep 0.1
done
pkill -9 -x Rastro 2>/dev/null || true
