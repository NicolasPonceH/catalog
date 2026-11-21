import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Imagen en blanco y negro puro, 1 bit por punto, filas de izquierda a derecha.
/// El bit más alto de cada byte es el punto de más a la izquierda (formato ESC/POS).
class BitmapMono {
  BitmapMono(this.ancho, this.alto, this.bits);

  final int ancho;
  final int alto;
  final Uint8List bits;

  int get anchoBytes => (ancho + 7) >> 3;

  bool negro(int x, int y) => bits[y * anchoBytes + (x >> 3)] & (0x80 >> (x & 7)) != 0;
}

/// Pasa la imagen a blanco y negro con un umbral (sin tramado: QR y barras nítidos).
Future<BitmapMono> aMonocromo(ui.Image imagen, {int umbral = 128}) async {
  final datos = (await imagen.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final w = imagen.width;
  final h = imagen.height;
  final wb = (w + 7) >> 3;
  final bits = Uint8List(wb * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final a = datos.getUint8(i + 3);
      final lum = a < 128
          ? 255
          : (datos.getUint8(i) * 299 + datos.getUint8(i + 1) * 587 + datos.getUint8(i + 2) * 114) ~/ 1000;
      if (lum < umbral) bits[y * wb + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return BitmapMono(w, h, bits);
}

/// PNG del bitmap (para compartir el sticker como imagen o revisarlo).
Future<Uint8List> pngDeMonocromo(BitmapMono b) async {
  final rgba = Uint8List(b.ancho * b.alto * 4);
  for (var y = 0; y < b.alto; y++) {
    for (var x = 0; x < b.ancho; x++) {
      final v = b.negro(x, y) ? 0 : 255;
      final i = (y * b.ancho + x) * 4;
      rgba[i] = v;
      rgba[i + 1] = v;
      rgba[i + 2] = v;
      rgba[i + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, b.ancho, b.alto, ui.PixelFormat.rgba8888, completer.complete);
  final img = await completer.future;
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}
