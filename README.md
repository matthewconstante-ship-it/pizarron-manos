# pizarron-manos — Pizarrón que se dibuja con las manos

Dibuja en un pizarrón con la cámara del Mac: la pinza (pulgar + índice) es el lápiz.

```
Cámara ─▶ python/manos.py (MediaPipe): detecta las manos
             │  OSC 127.0.0.1:12000  (/h1/x, /h1/y, /h1/pinch, /h1/on, igual para h2)
             ▼
          Processing: processing/pizarron/pizarron.pde
```

## Cómo se usa

- **Pinza** (pulgar + índice juntos) = dibujar · **mano abierta** = mover el cursor
- **Barra de arriba**: deja el dedo quieto ~1 s sobre un botón (se llena un anillo)
  - 7 colores y 3 grosores
  - **Goma**: convierte el lápiz en borrador (cursor rojo); haz pinza para borrar. Elige un color para volver a dibujar
  - **Deshacer** último trazo · **Borrar** todo · **Guardar** PNG en la carpeta del sketch
- Las dos manos pueden dibujar a la vez
- Teclas: `z` deshacer, `c` borrar, `s` guardar, `m` espejo

## Instalación (solo la primera vez)

1. **Processing 4** con la librería **oscP5** (*Sketch › Import Library › Manage Libraries*).
2. **Python 3.13** y el detector:
   ```bash
   cd python
   python3.13 -m venv .venv && .venv/bin/pip install -r requirements.txt
   curl -L -o hand_landmarker.task https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
   ```
3. Da permiso de **cámara** a la Terminal (*Ajustes del Sistema › Privacidad y seguridad › Cámara*).

## Arrancar

1. `python/run_manos.sh` — se abre una ventana con la cámara y tus manos dibujadas (`q` para salir).
   Opciones: `--no-preview`, `--camera N`.
2. Abre `processing/pizarron/pizarron.pde` en Processing y pulsa ▶.

## Notas

- El pizarrón redibuja todos los trazos cada fotograma: en Macs Apple Silicon una capa
  `PGraphics` P2D aparte no se mostraba en pantalla.
- Proyecto hermano: [manos_particulas](https://github.com/matthewconstante-ship-it/manos_particulas)
  (las manos sueltan partículas; versión con TouchDesigner o con Python).
