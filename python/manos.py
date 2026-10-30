"""Detecta las manos con la cámara (MediaPipe) y las envía a Processing por OSC.

Envía los mismos mensajes que manos_bridge.py de TouchDesigner, así que el
sketch processing/manos_particulas funciona igual con este ayudante:

    /h1/x, /h1/y   punta del dedo índice, 0..1 (y hacia arriba)
    /h1/pinch      distancia pulgar-índice (pequeña = pinza)
    /h1/on         1 si la mano se ve, 0 si no
    (igual para h2)

h1 = mano que MediaPipe etiqueta "Left", h2 = "Right" (si ambas tienen la
misma etiqueta, la segunda va al hueco libre).

Uso:  ./run_manos.sh            (o: .venv/bin/python manos.py)
      --no-preview   sin ventana de cámara (un poco más rápido)
      --camera N     usar otra cámara (por defecto 0)
En la ventana de vista previa: q o Esc para salir.
"""

import argparse
import math
import os
import time

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python import vision
from pythonosc.udp_client import SimpleUDPClient

PROCESSING_HOST = '127.0.0.1'
PROCESSING_PORT = 12000
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'hand_landmarker.task')

THUMB_TIP = 4
INDEX_TIP = 8
SLOTS = {'Left': 0, 'Right': 1}
COLORS = [(0, 140, 255), (255, 160, 0)]  # BGR: naranja (h1), azul (h2), como en Processing


def assign_slots(result):
    """Devuelve [mano_h1, mano_h2], cada una una lista de 21 landmarks o None."""
    slots = [None, None]
    leftovers = []
    for landmarks, handedness in zip(result.hand_landmarks, result.handedness):
        slot = SLOTS.get(handedness[0].category_name, 0)
        if slots[slot] is None:
            slots[slot] = landmarks
        else:
            leftovers.append(landmarks)
    for landmarks in leftovers:
        if None in slots:
            slots[slots.index(None)] = landmarks
    return slots


def send_hands(client, slots):
    for i, hand in enumerate(slots):
        prefix = '/h{}/'.format(i + 1)
        if hand is None:
            client.send_message(prefix + 'on', 0.0)
            continue
        tip, thumb = hand[INDEX_TIP], hand[THUMB_TIP]
        pinch = math.dist((tip.x, tip.y, tip.z), (thumb.x, thumb.y, thumb.z))
        client.send_message(prefix + 'x', float(tip.x))
        client.send_message(prefix + 'y', float(1.0 - tip.y))
        client.send_message(prefix + 'pinch', float(pinch))
        client.send_message(prefix + 'on', 1.0)


def draw_preview(frame, slots):
    h, w = frame.shape[:2]
    for i, hand in enumerate(slots):
        if hand is None:
            continue
        points = [(int(p.x * w), int(p.y * h)) for p in hand]
        for c in vision.HandLandmarksConnections.HAND_CONNECTIONS:
            cv2.line(frame, points[c.start], points[c.end], COLORS[i], 2)
        for p in points:
            cv2.circle(frame, p, 3, (255, 255, 255), -1)
        cv2.circle(frame, points[INDEX_TIP], 10, COLORS[i], 2)
    # Espejo solo en la vista previa, para que se vea natural
    return cv2.flip(frame, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--camera', type=int, default=0)
    parser.add_argument('--no-preview', action='store_true')
    args = parser.parse_args()

    cap = cv2.VideoCapture(args.camera)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)  # suficiente para MediaPipe y más rápido
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    if not cap.isOpened():
        raise SystemExit('No puedo abrir la cámara {}. ¿Diste permiso de cámara a la Terminal '
                         '(Ajustes del Sistema > Privacidad y seguridad > Cámara)?'.format(args.camera))

    options = vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
    )
    client = SimpleUDPClient(PROCESSING_HOST, PROCESSING_PORT)
    print('[manos] Enviando OSC a {}:{}  (q o Esc para salir)'.format(PROCESSING_HOST, PROCESSING_PORT))

    frames, last_report = 0, time.time()
    start = time.monotonic()
    with vision.HandLandmarker.create_from_options(options) as landmarker:
        while True:
            ok, frame = cap.read()
            if not ok:
                print('[manos] La cámara no devolvió imagen; reintentando…')
                time.sleep(0.1)
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            timestamp_ms = int((time.monotonic() - start) * 1000)
            result = landmarker.detect_for_video(image, timestamp_ms)

            slots = assign_slots(result)
            send_hands(client, slots)

            frames += 1
            now = time.time()
            if now - last_report >= 2:
                print('[manos] fps={:.1f}  mano1={}  mano2={}'.format(
                    frames / (now - last_report),
                    'si' if slots[0] else 'no',
                    'si' if slots[1] else 'no'))
                frames, last_report = 0, now

            if not args.no_preview:
                cv2.imshow('manos (q para salir)', draw_preview(frame, slots))
                if cv2.waitKey(1) & 0xFF in (ord('q'), 27):
                    break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
