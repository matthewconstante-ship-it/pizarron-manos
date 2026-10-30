#!/bin/bash
# Arranca el detector de manos (Python + MediaPipe) -> Processing por OSC
cd "$(dirname "$0")"
exec .venv/bin/python -u manos.py "$@"
