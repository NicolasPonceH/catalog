import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/backup/auto.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/dispositivo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/data/migraciones.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/ajustes_screen.dart';
import 'package:catalog/features/compra_form_screen.dart';
import 'package:catalog/features/historial_screen.dart';
import 'package:catalog/reports/excel.dart';
import 'package:catalog/system/notificaciones.dart';
import 'package:catalog/theme.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'responsivo_test.dart' show cargarFuentes;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  test('referencia de precio por código de fábrica y filtro Sin imprimir', () async {
    final base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
    addTearDown(base.cerrar);
    final repo = ComprasRepo(base);

    final c1 = await repo.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 18, 10),
      vendedor: 'Taller A',
      precio: 60000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      codigoFabrica: '0d140',
      autos: 'Toyota Yaris 2012',
    ));
    final c2 = await repo.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 20, 15),
      vendedor: 'Taller B',
      precio: 70000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      codigoFabrica: '0D140',
      autos: 'Toyota Yaris 2014',
    ));
    // Una anulada con el mismo código no debe distorsionar la referencia ni contar como sin imprimir.
    final c3 = await repo.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 21, 9),
      vendedor: 'Taller C',
      precio: 999000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      codigoFabrica: '0D140',
    ));
    await repo.anular(c3.id, 'error');

    final ref = await repo.referenciaCodigoFabrica(' 0d140 ');
    expect(ref, isNotNull);
    expect(ref!.cantidad, 2);
    expect(ref.ultimoPrecio, 70000);
    expect(ref.promedio, 65000);
    expect(ref.minimo, 60000);
    expect(ref.maximo, 70000);
    expect(ref.ultimoAutos, 'Toyota Yaris 2014');

    // Sin imprimir: al principio hay 2 activas con 0 impresiones.
    expect(await repo.contarSinImprimir(), 2);
    await repo.marcarImpresion(c1.id);
    expect(await repo.contarSinImprimir(), 1);
    final pendientes = await repo.historial(const FiltroHistorial(soloSinImprimir: true));
    expect(pendientes.map((x) => x.id).toList(), [c2.id]);
  });

  test('migración v1 -> v2, ganancia neta de un lote y Excel con utilidad', () async {
    final dir = await Directory.systemTemp.createTemp('catalog_mig_v2_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final ruta = p.join(dir.path, 'vieja_v1.db');

    // Crea una base en esquema v1 (como las de CataLog 1.0 a 1.4).
    final dbV1 = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final sql in migraciones[1]!) {
            await db.execute(sql);
          }
        },
      ),
    );
    await dbV1.insert('lotes', {'nombre': 'Lote antiguo', 'creado_en': 1700000000000, 'notas': ''});
    await dbV1.close();

    // Al abrir con CatalogDb se migra sola a la versión 2 sin perder el lote.
    final base = await CatalogDb.abrir(ruta: ruta, fabrica: databaseFactoryFfi);
    addTearDown(base.cerrar);
    final compras = ComprasRepo(base);
    final lotes = LotesRepo(base);

    final c1 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 22, 11),
      vendedor: 'Juan',
      precio: 120000,
      motor: Motor.diesel,
      material: TipoMaterial.dpf,
    ));
    final c2 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 22, 12),
      vendedor: 'Pedro',
      precio: 80000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
    ));
    final entrega = await lotes.crear(nombre: 'Entrega fundición');
    await lotes.agregarEscaneado(entrega.id, c1.codigo);
    await lotes.agregarEscaneado(entrega.id, c2.codigo);
    await lotes.cerrar(entrega.id, montoRecibido: 260000, actualizarMonto: true);

    final lista = await lotes.listar();
    expect(lista.length, 2);
    final actualizado = lista.firstWhere((l) => l.lote.id == entrega.id);
    expect(actualizado.resumen.total, 200000);
    expect(actualizado.lote.montoRecibido, 260000);
    expect(actualizado.ganancia, 60000);

    // El Excel del lote incluye MONTO RECIBIDO y UTILIDAD NETA.
    final items = await lotes.items(entrega.id);
    final excel = Excel.decodeBytes(excelDeLote(actualizado.lote, items));
    final hoja = excel['Lote'];
    String? txt(CellValue? v) => v is TextCellValue ? v.value.toString() : null;
    int? ent(CellValue? v) => v is IntCellValue ? v.value : null;

    final filaTarjetas = hoja.rows.indexWhere((f) => txt(f.first?.value) == 'COSTO PAGADO');
    expect(filaTarjetas, greaterThan(0));
    expect(ent(hoja.rows[filaTarjetas + 1][0]?.value), 200000);
    expect(ent(hoja.rows[filaTarjetas + 1][2]?.value), 260000);
    expect(ent(hoja.rows[filaTarjetas + 1][4]?.value), 60000);
    expect(txt(hoja.rows.last.first?.value), 'UTILIDAD NETA');
    expect(ent(hoja.rows.last[7]?.value), 60000);
  });

  test('notificaciones locales: respaldo en vivo y recordatorio diario', () async {
    final dir = await Directory.systemTemp.createTemp('catalog_notif_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final llamadas = <MethodCall>[];
    const canal = MethodChannel('cl.catalog/sistema');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, (call) async {
      llamadas.add(call);
      return switch (call.method) {
        'guardarEnDescargas' => 'Descargas/Respaldo CataLog/${call.arguments['nombre']}',
        'mostrarNotificacion' || 'programarRecordatorio' || 'pedirPermisoNotificaciones' => true,
        _ => null,
      };
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

    final base = await CatalogDb.abrir(ruta: p.join(dir.path, 'catalog.db'), fabrica: databaseFactoryFfi);
    addTearDown(base.cerrar);
    final dispositivo = await AjustesDispositivo.abrir(dir);
    final ahora = DateTime(2026, 11, 24, 18, 30);
    final repo = ComprasRepo(base, reloj: () => ahora);
    final c = await repo.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 24, 14, 0),
      vendedor: 'Taller Norte',
      precio: 90000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
    ));
    final lote = await LotesRepo(base, reloj: () => ahora).crear(nombre: 'Bodega');
    await LotesRepo(base, reloj: () => ahora).agregarEscaneado(lote.id, c.codigo);

    // Respaldo automático emite notificación "enCurso: true" y luego "enCurso: false".
    await respaldoAutomatico(base: base, carpeta: dir, dispositivo: dispositivo, ahora: ahora);
    final notifsRespaldo = llamadas.where((m) => m.method == 'mostrarNotificacion').toList();
    expect(notifsRespaldo.length, 2);
    expect((notifsRespaldo.first.arguments as Map)['enCurso'], isTrue);
    expect((notifsRespaldo.last.arguments as Map)['enCurso'], isFalse);

    // Recordatorio diario junta stickers sin imprimir, lote abierto y resumen de hoy.
    await Notificaciones.sincronizarRecordatorioDiario(base: base, dispositivo: dispositivo, ahora: ahora);
    final prog = llamadas.lastWhere((m) => m.method == 'programarRecordatorio').arguments as Map;
    expect(prog['activo'], isTrue);
    expect(prog['hora'], 20);
    expect(prog['cuerpo'] as String, contains('1 catalítico tiene su sticker pendiente'));
    expect(prog['cuerpo'] as String, contains('Lote abierto "Bodega"'));
    expect(prog['cuerpo'] as String, contains(r'Hoy registraste 1 catalítico por $90.000'));
  });

  testWidgets('UI v1.5: pastilla de referencia en Nueva compra, chip Sin imprimir y botón rojo Ubicar respaldo',
      (tester) async {
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var abrioCarpeta = 0;
    const canal = MethodChannel('cl.catalog/sistema');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(canal, (call) async {
      if (call.method == 'abrirCarpetaRespaldos') {
        abrioCarpeta++;
        return true;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(canal, null));

    late CatalogDb base;
    late Directory temp;
    late AjustesDispositivo dispositivo;
    await tester.runAsync(() async {
      await cargarFuentes();
      temp = await Directory.systemTemp.createTemp('cat_ui_v15_');
      dispositivo = await AjustesDispositivo.abrir(temp);
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      final repo = ComprasRepo(base);
      await repo.crear(DatosCompra(
        fechaCompra: DateTime.now().subtract(const Duration(hours: 2)),
        vendedor: 'Taller Rojas',
        precio: 65000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
        codigoFabrica: 'K4M2D',
        autos: 'Renault Symbol 2013',
      ));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        await base.cerrar();
        if (await temp.exists()) await temp.delete(recursive: true);
      });
    });

    Future<void> avanzar([int ms = 300]) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // 1) Pastilla de referencia automática al escribir K4M2D en Nueva compra.
    await tester.pumpWidget(AppScope(
      base: base,
      fotos: FotosStore(temp),
      dispositivo: dispositivo,
      child: MaterialApp(theme: catalogTheme(), home: const CompraFormScreen()),
    ));
    await avanzar();

    await tester.drag(find.byType(ListView).first, const Offset(0, -350));
    await avanzar();
    final campoCodigo = find.widgetWithText(TextFormField, 'Código grabado de fábrica');
    await tester.enterText(campoCodigo, 'k4m2d');
    await avanzar();

    expect(find.textContaining(r'Última vez: $65.000'), findsOneWidget);
    await tester.tap(find.text(r'Usar $65.000'));
    await avanzar();
    expect(find.text('65.000'), findsOneWidget);
    expect(find.text('Renault Symbol 2013'), findsOneWidget);

    // 2) Chip "Sin imprimir (1)" en Historial.
    await tester.pumpWidget(AppScope(
      base: base,
      fotos: FotosStore(temp),
      dispositivo: dispositivo,
      child: MaterialApp(theme: catalogTheme(), home: const HistorialScreen()),
    ));
    await avanzar();
    expect(find.text('Sin imprimir (1)'), findsOneWidget);

    // 3) Tarjeta roja "Ubicar respaldo" en Ajustes abre directo la carpeta nativa.
    await tester.pumpWidget(AppScope(
      base: base,
      fotos: FotosStore(temp),
      dispositivo: dispositivo,
      child: MaterialApp(theme: catalogTheme(), home: const AjustesScreen()),
    ));
    await avanzar();

    await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
    await avanzar();
    expect(find.text('Ubicar respaldo'), findsOneWidget);
    await tester.tap(find.text('Ubicar respaldo'));
    await avanzar();
    expect(abrioCarpeta, 1);
  });
}
