import 'raster.dart';

/// Arma el trabajo de impresión ESC/POS para un sticker:
///   ESC @          reinicia la impresora
///   GS v 0         imagen de bits, en franjas de hasta [filasPorFranja] filas
///   ESC d n        avanza n líneas para poder cortar el papel
/// Todo se envía de una vez (la librería Bluetooth agrega un salto de línea al
/// comienzo de cada envío).
List<int> trabajoImpresion(BitmapMono b, {int avance = 4, int filasPorFranja = 128}) {
  final salida = <int>[0x1B, 0x40];
  final wb = b.anchoBytes;
  for (var y = 0; y < b.alto; y += filasPorFranja) {
    final h = (b.alto - y) < filasPorFranja ? b.alto - y : filasPorFranja;
    salida.addAll([0x1D, 0x76, 0x30, 0x00, wb & 0xFF, (wb >> 8) & 0xFF, h & 0xFF, (h >> 8) & 0xFF]);
    salida.addAll(b.bits.sublist(y * wb, (y + h) * wb));
  }
  salida.addAll([0x1B, 0x64, avance]);
  return salida;
}
