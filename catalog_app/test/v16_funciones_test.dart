import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/backup/auto.dart';
import 'package:catalog/backup/respaldo.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/dispositivo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/data/sesiones.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/ajustes_screen.dart';
import 'package:catalog/features/compra_form_screen.dart';
import 'package:catalog/features/inicio_screen.dart';
import 'package:catalog/features/revision_supervisor_screen.dart';
import 'package:catalog/i18n.dart';
import 'package:catalog/reports/excel.dart';
import 'package:catalog/sync/wifi_sync.dart';
import 'package:catalog/system/notificaciones.dart';
import 'package:catalog/theme.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  setUp(() async {
    Idioma.actual = 'es';
    tempDir = await Directory.systemTemp.createTemp('catalog_v16_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v1.6: fotos ligeras por defecto, estadísticas y modos de respaldo (sobrescribir / expirar)', () async {
    final disp = await AjustesDispositivo.abrir(tempDir);
    expect(disp.calidadFotoElegida, 'ligera');
    expect(disp.ladoMaxFoto, 1024);
    expect(disp.calidadJpegFoto, 62);
    expect(disp.sobrescribirRespaldo, isTrue);
    expect(disp.diasExpiracionRespaldo, isNull);
    expect(nombreAutoRespaldo('CTL', DateTime(2026, 11, 24), sobrescribir: true), 'CataLog-auto-CTL.zip');

    await disp.guardar(AjustesDispositivo.modoRespaldo, 'expirar_7');
    expect(disp.sobrescribirRespaldo, isFalse);
    expect(disp.diasExpiracionRespaldo, 7);

    final fotos = FotosStore(tempDir);
    final orig = File(p.join(tempDir.path, 'muestra.jpg'))..writeAsBytesSync(List.filled(4096, 7));
    await fotos.guardar(orig.path);
    final (cant, bytes) = await fotos.estadisticas();
    expect(cant, 1);
    expect(bytes, 4096);
  });

  test('v1.6: sugerencias ordenadas por frecuencia de uso (vendedor y auto frecuente)', () async {
    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'freq.db'), fabrica: databaseFactoryFfi);
    final repo = ComprasRepo(db, reloj: () => DateTime(2026, 11, 24, 12));

    Future<void> registrar(String vendedor, String auto, DateTime f) => repo.crear(DatosCompra(
          fechaCompra: f,
          vendedor: vendedor,
          precio: 60000,
          motor: Motor.bencinero,
          material: TipoMaterial.ceramico,
          autos: auto,
        ));

    await registrar('Taller Hermanos Rojas', 'Toyota Hilux', DateTime(2026, 11, 20, 10));
    await registrar('Taller Hermanos Rojas', 'Toyota Hilux', DateTime(2026, 11, 21, 10));
    await registrar('Juan Mamani', 'Suzuki Swift', DateTime(2026, 11, 23, 10));

    final vendedores = await repo.sugerenciasFrecuentes('vendedor');
    final autos = await repo.sugerenciasFrecuentes('autos');
    expect(vendedores.first, 'Taller Hermanos Rojas');
    expect(autos.first, 'Toyota Hilux');
    await db.cerrar();
  });

  test('v1.6: sincronización Wi-Fi local bidireccional transfiere compras y fotos reales', () async {
    final dirEmisor = Directory(p.join(tempDir.path, 'emisor'))..createSync(recursive: true);
    final db = await CatalogDb.abrir(ruta: p.join(dirEmisor.path, 'catalog.db'), fabrica: databaseFactoryFfi);
    final repo = ComprasRepo(db, reloj: () => DateTime(2026, 11, 24, 15));
    await repo.guardarAjuste('prefijo', 'CTL');
    await repo.guardarAjuste('nombre', 'Jorge');
    await repo.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 24, 14),
      vendedor: 'Lubricentro Azapa',
      precio: 85000,
      motor: Motor.diesel,
      material: TipoMaterial.dpf,
      codigoFabrica: '1KD',
      autos: 'Toyota Hilux',
    ));
    Directory(p.join(dirEmisor.path, 'fotos')).createSync(recursive: true);
    File(p.join(dirEmisor.path, 'fotos', '100.jpg')).writeAsBytesSync([1, 2, 3, 4, 5]);

    final servidor = await ServidorWifiCatalog.iniciar(
      ip: '127.0.0.1',
      nombre: 'Jorge',
      prefijo: 'CTL',
      compras: 1,
      conFotos: true,
      anunciarUdp: false,
      generarZip: () => armarRespaldo(db, dirEmisor, incluirFotos: true, tipo: 'wifi'),
    );

    try {
      final qr = servidor.punto.aQr();
      final decodificado = PuntoWifiCatalog.deQr(qr)!;
      expect(decodificado.ip, '127.0.0.1');
      expect(decodificado.puerto, servidor.punto.puerto);
      expect(decodificado.nombre, 'Jorge');

      final recibidoBytes = await descargarPorWifi(decodificado);
      final contenido = leerRespaldo(recibidoBytes);
      expect(contenido.compras, 1);
      expect(contenido.nombre, 'Jorge');
      expect(contenido.prefijo, 'CTL');
      expect(contenido.fotos['100.jpg'], [1, 2, 3, 4, 5]);
    } finally {
      await servidor.cerrar();
      await db.cerrar();
    }
  });

  test('v1.6: notificaciones periódicas, aviso al salir de la app y Excel de Revisión de Supervisor', () async {
    final llamadas = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('cl.catalog/sistema'),
      (call) async {
        llamadas.add(call);
        return true;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('cl.catalog/sistema'),
        null,
      );
    });

    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'notif.db'), fabrica: databaseFactoryFfi);
    addTearDown(db.cerrar);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 24, 16));
    final lotes = LotesRepo(db, reloj: () => DateTime(2026, 11, 24, 16));
    final disp = await AjustesDispositivo.abrir(tempDir);

    final c1 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 24, 15, 30),
      vendedor: 'Taller Sur',
      precio: 90000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
    ));
    final lote = await lotes.crear(nombre: 'Lote Bodega');
    await lotes.agregarEscaneado(lote.id, c1.codigo);

    await Notificaciones.sincronizarRecordatorioDiario(
      base: db,
      dispositivo: disp,
      ahora: DateTime(2026, 11, 24, 16, 10),
    );
    final prog = llamadas.lastWhere((c) => c.method == 'programarRecordatorio');
    final argsProg = prog.arguments as Map;
    expect(argsProg['intervaloMinutos'], 60);
    expect((argsProg['cuerpoPeriodico'] as String), contains('Lote Bodega'));

    await Notificaciones.avisarAlSalirDeApp(
      base: db,
      dispositivo: disp,
      ahora: DateTime(2026, 11, 24, 17, 0),
    );
    final salida = llamadas.lastWhere((c) => c.method == 'mostrarNotificacion');
    expect(((salida.arguments as Map)['titulo'] as String).toLowerCase(), contains('sticker'));

    // Excel de Revisión de Supervisor
    final bytesExcel = excelDeRevisionSupervisor(
      [
        FilaRevisionExcel(codigo: c1.codigo, compra: c1, escaneadoEn: DateTime(2026, 11, 24, 16, 45)),
        const FilaRevisionExcel(codigo: 'CTL-261124-0099'),
      ],
      comprador: 'Jorge',
      prefijo: 'CTL',
    );
    final libro = Excel.decodeBytes(bytesExcel);
    expect(libro.tables.containsKey('Revisión'), isTrue);

    await db.cerrar();
  });

  testWidgets('v1.6 UI: avisos con borde en Inicio, chips rápidos en Nueva compra y Ajustes sin Cambiar de sesión',
      (tester) async {
    late CatalogDb db;
    late AjustesDispositivo disp;
    late Sesiones sesiones;
    late Directory uiDir;

    await tester.runAsync(() async {
      uiDir = await Directory.systemTemp.createTemp('catalog_v16_ui_');
      db = await CatalogDb.abrir(ruta: p.join(uiDir.path, 'ui.db'), fabrica: databaseFactoryFfi);
      final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 24, 14));
      final lotes = LotesRepo(db, reloj: () => DateTime(2026, 11, 24, 14));
      await compras.guardarAjuste('prefijo', 'CTL');
      await compras.guardarAjuste('nombre', 'Jorge');
      final c = await compras.crear(DatosCompra(
        fechaCompra: DateTime(2026, 11, 24, 13),
        vendedor: 'Taller Hermanos Rojas',
        precio: 75000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
        autos: 'Toyota Hilux',
      ));
      final lote = await lotes.crear(nombre: 'Entrega Norte');
      await lotes.agregarEscaneado(lote.id, c.codigo);

      disp = await AjustesDispositivo.abrir(uiDir);
      sesiones = Sesiones(uiDir, p.join(uiDir.path, 'ui.db'));
    });

    addTearDown(() async {
      await tester.runAsync(() async {
        await db.cerrar();
        if (await uiDir.exists()) await uiDir.delete(recursive: true);
      });
    });

    Future<void> bombear([int ms = 300]) async {
      for (var k = 0; k < 2; k++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      }
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Widget envolver(Widget hijo) => AppScope(
          base: db,
          fotos: FotosStore(uiDir),
          sesion: sesiones.principal,
          sesiones: sesiones,
          dispositivo: disp,
          child: MaterialApp(theme: catalogTheme(Paleta.clara), home: hijo),
        );

    // 1. Inicio destaca compra sin sticker y lote abierto
    await tester.pumpWidget(envolver(const InicioScreen()));
    await bombear();
    expect(find.textContaining('No se le ha sacado el sticker', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('1 catalítico sin sticker impreso', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Lote abierto: "Entrega Norte"', skipOffstage: false), findsOneWidget);

    // 2. Nueva compra muestra chips rápidos de vendedor frecuente al enfocar
    await tester.pumpWidget(envolver(const CompraFormScreen()));
    await bombear();
    await tester.tap(find.widgetWithText(TextFormField, 'Vendedor'));
    await bombear(200);
    expect(find.text('Taller Hermanos Rojas'), findsWidgets);

    // 3. Ajustes ya NO muestra "Cambiar de sesión", y sí muestra Revisión de Supervisor y Sincronizar por Wi-Fi
    await tester.pumpWidget(envolver(const AjustesScreen()));
    await bombear();
    expect(find.text('Cambiar de sesión'), findsNothing);
    expect(find.text('Revisión de Supervisor', skipOffstage: false), findsOneWidget);
    expect(find.text('Sincronizar por Wi-Fi', skipOffstage: false), findsOneWidget);

    // 4. Pantalla de Revisión de Supervisor carga el catálogo y permite filtrar
    await tester.pumpWidget(envolver(const RevisionSupervisorScreen(iniciarConCamara: false)));
    await bombear();
    expect(find.text('Revisión de Supervisor'), findsOneWidget);
    expect(find.text('Excel'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await bombear(100);
  });
}
