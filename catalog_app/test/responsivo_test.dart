import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fuentes reales de la app (con la fuente de pruebas las letras son más anchas).
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
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  const pantallas = [
    ('teléfono chico con letra grande', Size(320, 640), 1.3),
    ('teléfono normal', Size(393, 851), 1.0),
    ('tablet o teléfono de lado', Size(1024, 700), 1.0),
  ];

  for (final (nombre, tamano, letra) in pantallas) {
    testWidgets('inicio y nueva compra sin desbordes: $nombre', (tester) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = letra;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      late CatalogDb base;
      await tester.runAsync(() async {
        await cargarFuentes();
        base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      });
      await tester.pumpWidget(AppScope(base: base, fotos: FotosStore(Directory.systemTemp), child: const CatalogApp()));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(find.text('Nueva compra'), findsOneWidget);

      // En pantallas chicas el botón puede quedar más abajo: se baja hasta él.
      await tester.ensureVisible(find.text('Nueva compra'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Nueva compra'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Fecha y hora de compra'), findsOneWidget);
      // Recorre todo el formulario hasta el botón de guardar.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Guardar compra'), findsOneWidget);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.runAsync(base.cerrar);
    });
  }
}
