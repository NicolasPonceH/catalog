import 'dart:io';

import 'package:catalog/printing/escpos.dart';
import 'package:catalog/printing/etiqueta.dart';
import 'package:catalog/printing/raster.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga las fuentes reales de la app para que el sticker se dibuje como en el teléfono.
Future<void> cargarFuentes() async {
  final familias = {
    'SpaceGrotesk': ['SpaceGrotesk_400Regular.ttf', 'SpaceGrotesk_500Medium.ttf', 'SpaceGrotesk_700Bold.ttf'],
    'IBMPlexMono': ['IBMPlexMono_400Regular.ttf', 'IBMPlexMono_500Medium.ttf'],
  };
  for (final e in familias.entries) {
    final loader = FontLoader(e.key);
    for (final archivo in e.value) {
      loader.addFont(File('assets/fonts/$archivo').readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }
}

void main() {
  final datos = DatosEtiqueta(
    codigo: 'CTL-261121-0007',
    fechaCompra: DateTime(2026, 11, 21, 10, 42),
    tipo: 'Cerámico · Bencinero · Original',
  );

  testWidgets('el sticker sale en blanco y negro al ancho de la impresora', (tester) async {
    await tester.runAsync(() async {
      await cargarFuentes();
      final salida = Directory('build/pruebas')..createSync(recursive: true);

      for (final ancho in [384, 576]) {
        final mono = await aMonocromo(await renderizarEtiqueta(datos, anchoPx: ancho));
        expect(mono.ancho, ancho);
        expect(mono.alto, (altoEtiqueta * ancho / anchoEtiqueta).round());

        // Proporción de puntos negros razonable (ni vacío ni todo negro).
        var negros = 0;
        for (var y = 0; y < mono.alto; y++) {
          for (var x = 0; x < mono.ancho; x++) {
            if (mono.negro(x, y)) negros++;
          }
        }
        final proporcion = negros / (mono.ancho * mono.alto);
        expect(proporcion, inInclusiveRange(0.05, 0.5));

        // Las esquinas quedan blancas (margen para el corte).
        expect(mono.negro(0, 0), isFalse);
        expect(mono.negro(ancho - 1, mono.alto - 1), isFalse);

        // Imagen para revisarla con un lector de códigos fuera de la app.
        File('${salida.path}/sticker-${ancho == 384 ? 58 : 80}mm.png')
            .writeAsBytesSync(await pngDeMonocromo(mono));
        expect(trabajoImpresion(mono).length, greaterThan(mono.anchoBytes * mono.alto));
      }
    });
  });
}
