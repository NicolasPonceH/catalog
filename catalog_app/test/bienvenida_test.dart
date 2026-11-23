import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/bienvenida.dart';
import 'package:catalog/features/presentacion_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'responsivo_test.dart' show cargarFuentes;

Future<void> _avanzar(WidgetTester t, {int ms = 1000}) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  test('saludo según la hora e iniciales del nombre', () {
    expect(saludoPorHora(DateTime(2026, 11, 23, 8)), 'Buenos días');
    expect(saludoPorHora(DateTime(2026, 11, 23, 15)), 'Buenas tardes');
    expect(saludoPorHora(DateTime(2026, 11, 23, 22)), 'Buenas noches');
    expect(saludoPorHora(DateTime(2026, 11, 23, 3)), 'Buenas noches');
    expect(iniciales('pedro soto rojas'), 'PS');
    expect(iniciales('  Ana  '), 'A');
    expect(iniciales(''), '');
  });

  Future<CatalogDb> baseConDatos(WidgetTester tester) async {
    late CatalogDb base;
    await tester.runAsync(() async {
      await cargarFuentes();
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      final repo = ComprasRepo(base);
      await repo.guardarAjuste('nombre', 'Pedro Soto');
      await repo.crear(DatosCompra(
        fechaCompra: DateTime.now().subtract(const Duration(minutes: 5)),
        vendedor: 'Taller de ejemplo',
        precio: 75000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
      ));
    });
    return base;
  }

  for (final (nombre, tamano, letra) in [
    ('teléfono chico con letra grande', const Size(320, 640), 1.3),
    ('teléfono normal', const Size(393, 851), 1.0),
  ]) {
    testWidgets('bienvenida: saluda, cuenta lo del mes y entra sola ($nombre)', (tester) async {
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = letra;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final base = await baseConDatos(tester);
      var entro = false;
      await tester.pumpWidget(AppScope(
        base: base,
        fotos: FotosStore(Directory.systemTemp),
        child: MaterialApp(home: Bienvenida(bloqueada: false, alEntrar: () => entro = true)),
      ));
      await _avanzar(tester, ms: 2600);
      expect(find.text('Pedro'), findsOneWidget);
      expect(find.text('PS'), findsOneWidget);
      expect(find.text(r'$75.000'), findsOneWidget);
      expect(find.text('Mis compras'), findsOneWidget);
      expect(entro, isFalse);

      // Sin bloqueo entra sola después de la animación.
      await _avanzar(tester, ms: 2400);
      expect(entro, isTrue);
      await tester.runAsync(base.cerrar);
    });
  }

  testWidgets('presentación: recorre las páginas y guarda nombre y prefijo', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final base = await baseConDatos(tester);
    final navegador = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppScope(
      base: base,
      fotos: FotosStore(Directory.systemTemp),
      child: MaterialApp(navigatorKey: navegador, home: const Scaffold(body: Text('Inicio'))),
    ));
    late Future<bool> resultado;
    resultado = abrirPresentacion(navegador.currentState!);
    await _avanzar(tester);
    expect(find.text('Bienvenido a CataLog'), findsOneWidget);

    for (final titulo in [
      'Anota cada compra',
      'Imprime su sticker',
      'Escanea y arma lotes',
      'Reportes en Excel',
      'Tus datos, seguros',
      'Antes de empezar',
    ]) {
      await tester.tap(find.text('Siguiente'));
      await _avanzar(tester, ms: 700);
      expect(find.text(titulo), findsOneWidget, reason: titulo);
    }

    // Última página: nombre, prefijo y vista previa del código.
    await tester.enterText(find.byType(TextField).first, 'María González');
    await tester.enterText(find.byType(TextField).last, 'mgz');
    await _avanzar(tester, ms: 400);
    expect(find.text('MG'), findsOneWidget);
    expect(find.textContaining('MGZ-'), findsOneWidget);

    await tester.tap(find.text('Empezar'));
    await _avanzar(tester, ms: 800);
    expect(await resultado, isTrue);
    await tester.runAsync(() async {
      final repo = ComprasRepo(base);
      expect(await repo.leerAjuste('nombre'), 'María González');
      expect(await repo.leerAjuste('prefijo'), 'MGZ');
      await base.cerrar();
    });
  });

  testWidgets('presentación: "Saltar" no cambia nada', (tester) async {
    final base = await baseConDatos(tester);
    final navegador = GlobalKey<NavigatorState>();
    await tester.pumpWidget(AppScope(
      base: base,
      fotos: FotosStore(Directory.systemTemp),
      child: MaterialApp(navigatorKey: navegador, home: const Scaffold(body: Text('Inicio'))),
    ));
    final resultado = abrirPresentacion(navegador.currentState!);
    await _avanzar(tester);
    await tester.tap(find.text('Saltar'));
    await _avanzar(tester);
    expect(await resultado, isFalse);
    expect(find.text('Inicio'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await ComprasRepo(base).leerAjuste('prefijo'), isNull);
      await base.cerrar();
    });
  });
}
