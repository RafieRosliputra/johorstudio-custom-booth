#!/bin/bash
# Double-click file ni dalam Finder untuk build app.
cd "$(dirname "$0")"
./scripts/build_app.sh
echo
read -n 1 -s -r -p "Tekan apa-apa kekunci untuk tutup…"
