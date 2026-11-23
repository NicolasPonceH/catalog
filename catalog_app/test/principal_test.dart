import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/bienvenida.dart';
import 'package:catalog/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'responsivo_test.dart' show cargarFuentes;

Future<void> _avanzar(WidgetTester t, {int ms = 1000}) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  Future<CatalogDb> base(WidgetTester tester) async {
    late CatalogDb b;
    await tester.runAsync(() async {
      await cargarFuentes();
      b = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      final repo = ComprasRepo(b);
      await repo.guardarAjuste('nombre', 'Pedro Soto');
      await repo.crear(DatosCompra(
        fechaCompra: DateTime.now().subtract(const Duration(minutes: 5)),
        vendedor: 'Taller de ejemplo',
        precio: 75000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
      ));
    });
    return b;
  }

  testWidgets('bloqueo: saluda, analiza la huella y no muestra montos', (tester) async {
    final b = await base(tester);
    var entro = false;
    await tester.pumpWidget(AppScope(
      base: b,
      fotos: FotosStore(Directory.systemTemp),
      child: MaterialApp(home: Bienvenida(bloqueada: true, alEntrar: () => entro = true)),
    ));
    await _avanzar(tester, ms: 600);
    expect(find.text('Hola, Pedro'), findsOneWidget);
    // Con la app bloqueada no se ven los montos.
    expect(find.text(r'$75.000'), findsNothing);
    expect(find.textContaining('Gastado'), findsNothing);

    // Al terminar la entrada pide la huella; en las pruebas no hay lector y falla.
    await _avanzar(tester, ms: 1500);
    // La llamada al lector (que en las pruebas no existe) termina en tiempo real.
    await _avanzar(tester, ms: 300);
    expect(find.text('No se reconoció. Toca para intentar de nuevo'), findsOneWidget);
    expect(entro, isFalse);
    await tester.runAsync(b.cerrar);
  });

  testWidgets('barra de abajo: cambia de pestaña y atrás vuelve al Inicio', (tester) async {
    final b = await base(tester);
    await tester.pumpWidget(AppScope(base: b, fotos: FotosStore(Directory.systemTemp), child: const CatalogApp()));
    await _avanzar(tester, ms: 500);
    expect(find.text('Nueva compra'), findsOneWidget);
    expect(find.byTooltip('Escanear sticker'), findsOneWidget);

    await tester.tap(find.text('Historial'));
    await _avanzar(tester, ms: 500);
    expect(find.text('Historial de compras'), findsOneWidget);

    await tester.tap(find.text('Reportes'));
    await _avanzar(tester, ms: 500);
    expect(find.text('Exportar a Excel'), findsOneWidget);

    // El botón "atrás" del teléfono vuelve al Inicio en vez de cerrar la app.
    await tester.binding.handlePopRoute();
    await _avanzar(tester, ms: 500);
    expect(find.text('Nueva compra'), findsOneWidget);
    await tester.runAsync(b.cerrar);
  });
}
