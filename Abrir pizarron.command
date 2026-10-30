#!/bin/bash
# Doble clic para abrir el pizarrón: arranca el detector de manos y el sketch.
# Al cerrar la ventana del pizarrón se apaga también el detector.
cd "$(dirname "$0")"

pkill -f "manos\.py" 2>/dev/null  # por si quedó un detector abierto (usa la cámara)

echo "Arrancando el detector de manos..."
python/run_manos.sh &
DETECTOR=$!
trap 'kill $DETECTOR 2>/dev/null' EXIT

echo "Abriendo el pizarrón... (cierra su ventana para terminar)"
/Applications/Processing.app/Contents/MacOS/Processing cli \
  --sketch="$PWD/processing/pizarron" \
  --output="${TMPDIR:-/tmp}/pizarron_build" --force --run 2>&1 | grep -v "sun.awt.X11"
