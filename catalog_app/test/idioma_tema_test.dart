import 'dart:io';

import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/dispositivo.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/data/sesiones.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/i18n.dart';
import 'package:catalog/main.dart';
import 'package:catalog/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'responsivo_test.dart' show cargarFuentes;

Future<void> _avanzar(WidgetTester t, {int ms = 500}) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  for (var i = 0; i < ms ~/ 100; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  tearDown(() {
    Idioma.actual = 'es';
    CatalogColors.paleta = Paleta.clara;
  });

  testWidgets('cambia de idioma Español a English, tema oscuro y alto contraste en vivo', (tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory temp;
    late CatalogDb base;
    late Sesiones sesiones;
    late AjustesDispositivo dispositivo;
    await tester.runAsync(() async {
      await cargarFuentes();
      temp = await Directory.systemTemp.createTemp('catalog_i18n_');
      sesiones = Sesiones(temp, p.join(temp.path, 'catalog.db'));
      dispositivo = await AjustesDispositivo.abrir(temp);
      // Ya vio la presentación para entrar directo al Inicio tras tocar la bienvenida.
      await dispositivo.guardar(AjustesDispositivo.presentacionVista, '1');
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      final repo = ComprasRepo(base);
      await repo.guardarAjuste('nombre', 'Nicolás Ponce');
      await repo.guardarAjuste('prefijo', 'CTL');
      final c = await repo.crear(DatosCompra(
        fechaCompra: DateTime.now().subtract(const Duration(minutes: 10)),
        vendedor: 'Taller Rojas',
        lugar: 'Av. Santa María',
        precio: 85000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
        autos: 'Toyota Yaris',
      ));
      final lotes = LotesRepo(base);
      final lote = await lotes.crear(nombre: 'Entrega norte');
      await lotes.agregarEscaneado(lote.id, c.codigo);
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await base.cerrar();
        if (await temp.exists()) await temp.delete(recursive: true);
      });
    });

    await tester.pumpWidget(CatalogRoot(
      sesiones: sesiones,
      dispositivo: dispositivo,
      sesion: sesiones.principal,
      base: base,
    ));
    await _avanzar(tester, ms: 600);
    // Salta la bienvenida tocando la pantalla.
    await tester.tapAt(const Offset(100, 100));
    await _avanzar(tester, ms: 800);

    expect(find.text('Nueva compra'), findsOneWidget);

    // Abre Ajustes y cambia a English, Oscuro y Alto contraste.
    await tester.tap(find.byTooltip('Ajustes'));
    await _avanzar(tester, ms: 500);
    expect(find.text('Idioma y sonido'), findsOneWidget);

    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await _avanzar(tester, ms: 400);

    // La misma pantalla de Ajustes ya cambió al inglés sin cerrarse.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Language & sound'), findsOneWidget);
    expect(dispositivo.idiomaElegido, 'en');

    // Sube de vuelta a la sección de Apariencia para activar Dark y High contrast.
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 500));
    await _avanzar(tester, ms: 300);
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.text('Dark'));
    await _avanzar(tester, ms: 300);
    expect(CatalogColors.paleta.oscura, isTrue);

    await tester.tap(find.byType(Switch).first);
    await _avanzar(tester, ms: 300);
    expect(CatalogColors.paleta.grosorBorde, 2);

    // Vuelve al Inicio y recorre todas las pestañas rediseñadas en inglés.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _avanzar(tester, ms: 400);
    expect(find.text('New purchase'), findsOneWidget);
    expect(find.text('Recent purchases'), findsOneWidget);

    await tester.tap(find.text('History'));
    await _avanzar(tester, ms: 400);
    expect(find.text('Purchase history'), findsOneWidget);
    expect(find.text('Unprinted (1)'), findsOneWidget);

    await tester.tap(find.text('Batches'));
    await _avanzar(tester, ms: 400);
    expect(find.text('Scanned batches'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Reports'));
    await _avanzar(tester, ms: 400);
    expect(find.text('Export to Excel'), findsOneWidget);
    expect(find.text('By type'), findsOneWidget);
    expect(find.text('By seller'), findsOneWidget);
  });

  for (final lang in ['es', 'en']) {
    testWidgets('ajustes sin desbordes en teléfono chico con letra grande ($lang)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      late Directory temp;
      late CatalogDb base;
      late Sesiones sesiones;
      late AjustesDispositivo dispositivo;
      await tester.runAsync(() async {
        await cargarFuentes();
        temp = await Directory.systemTemp.createTemp('cat_resp_$lang');
        sesiones = Sesiones(temp, p.join(temp.path, 'catalog.db'));
        dispositivo = await AjustesDispositivo.abrir(temp);
        await dispositivo.guardar(AjustesDispositivo.presentacionVista, '1');
        if (lang == 'en') await dispositivo.guardar(AjustesDispositivo.idioma, 'en');
        base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await base.cerrar();
          if (await temp.exists()) await temp.delete(recursive: true);
        });
      });

      await tester.pumpWidget(CatalogRoot(
        sesiones: sesiones,
        dispositivo: dispositivo,
        sesion: sesiones.principal,
        base: base,
      ));
      await _avanzar(tester, ms: 500);
      await tester.tapAt(const Offset(80, 80));
      await _avanzar(tester, ms: 700);
      await tester.tap(find.byTooltip(lang == 'en' ? 'Settings' : 'Ajustes'));
      await _avanzar(tester, ms: 500);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2500));
      await _avanzar(tester, ms: 300);
    });
  }
}
