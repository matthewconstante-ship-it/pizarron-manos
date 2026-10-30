// pizarron — dibuja en un pizarrón con las manos
//
// Usa el mismo detector de manos (python/manos.py o TouchDesigner), por OSC al
// puerto 12000: /h1/x, /h1/y, /h1/pinch, /h1/on (igual para h2).
//
// Cómo se usa:
//   - Pinza (pulgar + índice juntos) = lápiz apoyado: dibuja
//   - Mano abierta = lápiz levantado: solo mueve el cursor
//   - Barra de arriba: deja el dedo quieto encima de un botón ~1 s para elegirlo
//     (colores, grosor, goma, deshacer, borrar todo, guardar imagen)
//   - Goma: no borra al tocarla; convierte el lápiz en borrador. Elige un color
//     para volver a dibujar.
//   - Las dos manos pueden dibujar a la vez
//
// Teclas: z deshacer, c borrar todo, s guardar PNG, m espejo on/off
//
// Librería: oscP5
//
// Nota: cada fotograma se limpia la pantalla y se redibujan todos los trazos.
// (Una capa PGraphics P2D aparte no se mostraba en este Mac.)

import oscP5.*;

final int LISTEN_PORT = 12000;
final float PINCH_ON = 0.05;   // por debajo: se apoya el lápiz
final float PINCH_OFF = 0.08;  // por encima: se levanta (histéresis, evita cortes)
final int BAR_H = 90;
final int DWELL_FRAMES = 35;   // tiempo quieto sobre un botón para elegirlo
final int MIN_POINTS = 4;      // trazos más cortos se consideran accidentales
final float ERASER_SCALE = 4;  // la goma es 4 veces más gruesa que el lápiz

final color BOARD = #15181D;   // fondo del pizarrón

OscP5 osc;
Hand[] hands = { new Hand(), new Hand() };
ArrayList<Stroke> strokes = new ArrayList<Stroke>();
ArrayList<Button> buttons = new ArrayList<Button>();

color currentColor = #F5F5F0;
float currentSize = 8;
boolean eraser = false;
boolean mirror = true;
volatile int oscCount = 0;

String toast = "";  // aviso grande en pantalla tras usar un botón
int toastUntil = 0;

void settings() {
  size(1280, 720, P2D);
  pixelDensity(1);
  smooth(8);
}

void setup() {
  osc = new OscP5(this, LISTEN_PORT);
  buildToolbar();
}

void draw() {
  for (Hand h : hands) h.update();

  background(BOARD);
  drawStrokes(g);
  drawToolbar();
  for (Hand h : hands) h.drawCursor();
  drawToast();

  if (frameCount % 120 == 0) {
    println("[estado] fps=" + nf(frameRate, 0, 1) + "  osc/2s=" + oscCount
      + "  mano1=" + (hands[0].on ? (hands[0].penDown ? "dibuja" : "si") : "no")
      + "  mano2=" + (hands[1].on ? (hands[1].penDown ? "dibuja" : "si") : "no")
      + "  trazos=" + strokes.size());
    oscCount = 0;
  }
}

// ---------- Trazos ----------

class Stroke {
  ArrayList<PVector> points = new ArrayList<PVector>();
  color col;
  float size;
  boolean erase;

  Stroke(color col, float size, boolean erase) {
    this.col = col;
    this.size = size;
    this.erase = erase;
  }

  void add(PVector p) {
    if (!points.isEmpty() && PVector.dist(points.get(points.size() - 1), p) < 2) return;
    points.add(p.copy());
  }

  void draw(PGraphics pg) {
    pg.stroke(erase ? BOARD : col);
    pg.strokeWeight(erase ? size * ERASER_SCALE : size);
    pg.strokeCap(ROUND);
    pg.strokeJoin(ROUND);
    pg.noFill();
    if (points.size() == 1) {
      pg.point(points.get(0).x, points.get(0).y);
      return;
    }
    pg.beginShape();
    for (PVector p : points) pg.vertex(p.x, p.y);
    pg.endShape();
  }
}

// En orden: la goma son trazos del color del fondo pintados encima
void drawStrokes(PGraphics pg) {
  for (Stroke s : strokes) s.draw(pg);
}

void undo() {
  if (strokes.isEmpty()) { showMessage("No hay nada que deshacer"); return; }
  Stroke last = strokes.remove(strokes.size() - 1);
  for (Hand h : hands) if (h.current == last) h.current = null;
  showMessage("Último trazo deshecho (quedan " + strokes.size() + ")");
}

void clearAll() {
  strokes.clear();
  for (Hand h : hands) h.current = null;
  showMessage("Pizarrón borrado");
}

// Guarda solo el dibujo (sin barra ni cursores)
void saveImage() {
  PGraphics out = createGraphics(width, height);
  out.beginDraw();
  out.smooth();
  out.background(BOARD);
  drawStrokes(out);
  out.endDraw();
  String name = "pizarron-" + year() + nf(month(), 2) + nf(day(), 2) + "-" + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".png";
  out.save(sketchPath(name));
  showMessage("Imagen guardada: " + name);
}

void showMessage(String msg) {
  toast = msg;
  toastUntil = millis() + 1800;
  println("[pizarron] " + msg);
}

void drawToast() {
  if (millis() > toastUntil) return;
  textSize(28);
  float w = textWidth(toast) + 60;
  noStroke();
  fill(0, 200);
  rect(width / 2 - w / 2, height - 110, w, 60, 14);
  fill(255);
  textAlign(CENTER, CENTER);
  text(toast, width / 2, height - 80);
}

// ---------- Manos ----------

class Hand {
  volatile float rawX, rawY, pinch;
  volatile boolean rawOn;
  boolean on, penDown;
  PVector pos = new PVector();
  Stroke current;
  Button hover;
  int dwell;
  boolean used;  // el botón ya se activó: hay que salir y volver a entrar

  void update() {
    boolean wasOn = on;
    on = rawOn;
    if (!on) {
      penDown = false;
      liftPen();
      hover = null;
      return;
    }

    float x = (mirror ? 1 - rawX : rawX) * width;
    float y = (1 - rawY) * height;
    pos.lerp(x, y, 0, wasOn ? 0.45 : 1);  // suaviza el temblor de la cámara

    if (!penDown && pinch > 0 && pinch < PINCH_ON) penDown = true;
    else if (penDown && pinch > PINCH_OFF) penDown = false;

    if (pos.y < BAR_H) {
      liftPen();  // en la barra no se dibuja
      updateDwell();
      return;
    }
    hover = null;
    used = false;

    if (penDown) {
      if (current == null) {
        current = new Stroke(currentColor, currentSize, eraser);
        strokes.add(current);
      }
      current.add(pos);
    } else {
      liftPen();
    }
  }

  // Termina el trazo actual; si era casi un punto (pinza que parpadea), se descarta
  void liftPen() {
    if (current != null && current.points.size() < MIN_POINTS) strokes.remove(current);
    current = null;
  }

  void updateDwell() {
    Button b = buttonAt(pos.x, pos.y);
    if (b != hover) {
      hover = b;
      dwell = 0;
      used = false;
    } else if (b != null && !used && ++dwell >= DWELL_FRAMES) {
      b.activate();
      used = true;
    }
  }

  void drawCursor() {
    if (!on) return;
    float d = (eraser ? currentSize * ERASER_SCALE : currentSize) + 8;
    strokeWeight(2);
    if (eraser) {
      // La goma se ve como un círculo rojo del tamaño real que borra
      stroke(#D9434B);
      if (penDown) fill(217, 67, 75, 70); else noFill();
    } else {
      stroke(currentColor);
      if (penDown) fill(currentColor); else noFill();
    }
    circle(pos.x, pos.y, max(d, 18));

    // Anillo de progreso al elegir un botón
    if (hover != null && !used && dwell > 0) {
      noFill();
      stroke(255);
      strokeWeight(4);
      arc(pos.x, pos.y, 46, 46, -HALF_PI, -HALF_PI + TWO_PI * dwell / DWELL_FRAMES);
    }
  }
}

// ---------- Barra de herramientas ----------

class Button {
  float x, y, w, h;
  String kind, label;
  color col;
  float size;

  Button(String kind, String label, color col, float size, float x, float w) {
    this.kind = kind;
    this.label = label;
    this.col = col;
    this.size = size;
    this.x = x;
    this.y = 15;
    this.w = w;
    this.h = BAR_H - 30;
  }

  boolean contains(float px, float py) {
    return px >= x && px <= x + w && py >= y && py <= y + h;
  }

  boolean selected() {
    if (kind.equals("color")) return !eraser && currentColor == col;
    if (kind.equals("size")) return currentSize == size;
    if (kind.equals("eraser")) return eraser;
    return false;
  }

  void activate() {
    if (kind.equals("color")) { currentColor = col; eraser = false; showMessage("Color elegido"); }
    else if (kind.equals("size")) { currentSize = size; showMessage("Grosor " + int(size)); }
    else if (kind.equals("eraser")) {
      eraser = !eraser;
      showMessage(eraser ? "Goma activada: haz pinza para borrar" : "Goma desactivada: vuelves a dibujar");
    }
    else if (kind.equals("undo")) undo();
    else if (kind.equals("clear")) clearAll();
    else if (kind.equals("save")) saveImage();
  }

  void draw() {
    stroke(selected() ? color(255) : color(255, 50));
    strokeWeight(selected() ? 3 : 1);
    if (kind.equals("color")) fill(col);
    else if (kind.equals("eraser") && eraser) fill(#D9434B);
    else fill(40, 44, 52);
    rect(x, y, w, h, 10);

    fill(255);
    noStroke();
    textAlign(CENTER, CENTER);
    if (kind.equals("size")) {
      circle(x + w / 2, y + h / 2, size);
    } else if (label != null) {
      textSize(15);
      text(label, x + w / 2, y + h / 2);
    }
  }
}

void buildToolbar() {
  color[] palette = { #F5F5F0, #FFD93D, #FF5C5C, #4ADE80, #38BDF8, #C084FC, #FB923C };
  float x = 20;
  for (color c : palette) { buttons.add(new Button("color", null, c, 0, x, 60)); x += 70; }
  x += 20;
  for (float s : new float[] { 4, 10, 22 }) { buttons.add(new Button("size", null, 0, s, x, 60)); x += 70; }
  x += 20;
  buttons.add(new Button("eraser", "Goma", 0, 0, x, 90)); x += 100;
  buttons.add(new Button("undo", "Deshacer", 0, 0, x, 100)); x += 110;
  buttons.add(new Button("clear", "Borrar", 0, 0, x, 90)); x += 100;
  buttons.add(new Button("save", "Guardar", 0, 0, x, 90));
}

void drawToolbar() {
  noStroke();
  fill(0, 160);
  rect(0, 0, width, BAR_H);
  for (Button b : buttons) b.draw();
}

Button buttonAt(float px, float py) {
  for (Button b : buttons) if (b.contains(px, py)) return b;
  return null;
}

// ---------- Teclado y OSC ----------

void keyPressed() {
  if (key == 'z') undo();
  if (key == 'c') clearAll();
  if (key == 's') saveImage();
  if (key == 'm') mirror = !mirror;
}

// Llega en otro hilo: solo guardamos los valores
void oscEvent(OscMessage m) {
  oscCount++;
  String a = m.addrPattern();
  if (a.startsWith("/")) a = a.substring(1);
  if (a.length() < 4 || a.charAt(0) != 'h' || m.arguments().length == 0) return;

  int i = a.charAt(1) - '1';
  if (i < 0 || i >= hands.length) return;
  float v = m.get(0).floatValue();
  String field = a.substring(3);

  if (field.equals("x")) hands[i].rawX = v;
  else if (field.equals("y")) hands[i].rawY = v;
  else if (field.equals("pinch")) hands[i].pinch = v;
  else if (field.equals("on")) hands[i].rawOn = v > 0.5;
}
