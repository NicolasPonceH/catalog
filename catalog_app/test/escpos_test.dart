import 'dart:typed_data';

import 'package:catalog/printing/escpos.dart';
import 'package:catalog/printing/raster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arma el trabajo con reinicio, franjas GS v 0 y avance de papel', () {
    final b = BitmapMono(384, 300, Uint8List(48 * 300));
    final bytes = trabajoImpresion(b);

    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    // Primera franja: 48 bytes de ancho y 128 filas.
    expect(bytes.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 48, 0, 128, 0]);
    // Tres franjas (128 + 128 + 44 filas) y avance de 4 líneas al final.
    expect(bytes.length, 2 + 3 * 8 + 48 * 300 + 3);
    expect(bytes.sublist(bytes.length - 3), [0x1B, 0x64, 4]);
    final terceraFranja = 2 + 2 * (8 + 48 * 128);
    expect(bytes.sublist(terceraFranja, terceraFranja + 8), [0x1D, 0x76, 0x30, 0x00, 48, 0, 44, 0]);
  });

  test('el bit alto de cada byte es el punto de más a la izquierda', () {
    final bits = Uint8List(2)..[0] = 0x80;
    final b = BitmapMono(16, 1, bits);
    expect(b.negro(0, 0), isTrue);
    expect(b.negro(1, 0), isFalse);
  });
}
