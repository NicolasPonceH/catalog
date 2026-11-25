import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/backup/respaldo.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/dispositivo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/data/sesiones.dart';
import 'package:catalog/data/supervisor_repo.dart';
import 'package:catalog/domain/codigo.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/compra_form_screen.dart';
import 'package:catalog/features/ficha_saco_screen.dart';
import 'package:catalog/features/revision_supervisor_screen.dart';
import 'package:catalog/i18n.dart';
import 'package:catalog/printing/etiqueta.dart';
import 'package:catalog/printing/raster.dart';
import 'package:catalog/reports/excel.dart';
import 'package:catalog/reports/reporte.dart';
import 'package:catalog/theme.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _cargarFuentes() async {
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
  late Directory tempDir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  setUp(() async {
    Idioma.actual = 'es';
    tempDir = await Directory.systemTemp.createTemp('catalog_v17_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('v1.7: estado de llenado de cerámica y bloqueo de catalíticos repetidos entre lotes de comprador',
      () async {
    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'lotes_v17.db'), fabrica: databaseFactoryFfi);
    addTearDown(db.cerrar);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 10));
    final lotes = LotesRepo(db, reloj: () => DateTime(2026, 11, 25, 10));

    final c1 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 9, 15),
      vendedor: 'Taller Hnos. Rojas',
      precio: 140000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      llenado: NivelLlenado.tresCuartos,
      codigoFabrica: '0D140',
    ));
    expect(c1.llenado, NivelLlenado.tresCuartos);
    expect(c1.tipoConLlenado, contains('3/4'));

    final loteA = await lotes.crear(nombre: 'Lote Martes Mañana');
    final loteB = await lotes.crear(nombre: 'Lote Martes Tarde');

    expect((await lotes.agregarEscaneado(loteA.id, c1.codigo)).$1, ResultadoEscaneo.agregado);
    // En el mismo lote: yaEstaba
    expect((await lotes.agregarEscaneado(loteA.id, c1.codigo)).$1, ResultadoEscaneo.yaEstaba);
    // En otro lote distinto: bloqueado con enOtroLote
    expect((await lotes.agregarEscaneado(loteB.id, c1.codigo)).$1, ResultadoEscaneo.enOtroLote);
    final dueno = await lotes.loteDeCompra(c1.id, excluirLoteId: loteB.id);
    expect(dueno?.nombre, 'Lote Martes Mañana');
    expect((await lotes.resumen(loteB.id)).cantidad, 0);
  });

  test('v1.7: sincronización .zip (WhatsApp/Wi-Fi) filtrada por fechas solo empaqueta esas compras y fotos',
      () async {
    final dirOrigen = Directory(p.join(tempDir.path, 'origen'))..createSync(recursive: true);
    Directory(p.join(dirOrigen.path, 'fotos')).createSync(recursive: true);
    File(p.join(dirOrigen.path, 'fotos', 'vieja.jpg')).writeAsBytesSync([9, 9, 9]);
    File(p.join(dirOrigen.path, 'fotos', 'nueva.jpg')).writeAsBytesSync([1, 2, 3, 4]);

    final db = await CatalogDb.abrir(ruta: p.join(dirOrigen.path, 'catalog.db'), fabrica: databaseFactoryFfi);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 12));
    await compras.guardarAjuste('nombre', 'Jorge');
    await compras.guardarAjuste('prefijo', 'CTL');

    // Compra antigua (10 de noviembre)
    await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 10, 11),
      vendedor: 'Antiguo',
      precio: 90000,
      motor: Motor.bencinero,
      material: TipoMaterial.metalico,
      fotoPath: 'fotos/vieja.jpg',
    ));

    // Compra de hoy (25 de noviembre)
    final hoyCompra = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 11),
      vendedor: 'Taller Hoy',
      precio: 185000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      llenado: NivelLlenado.medio,
      fotoPath: 'fotos/nueva.jpg',
    ));

    final filtroHoy = FiltroEnvioCatalog(
      desde: DateTime(2026, 11, 25),
      hastaExclusivo: DateTime(2026, 11, 26),
      etiqueta: 'Hoy · 25/11/2026',
    );
    final (cant, monto) = await contarComprasParaEnvio(db, filtroHoy);
    expect(cant, 1);
    expect(monto, 185000);

    final zipBytes = await armarRespaldo(
      db,
      dirOrigen,
      incluirFotos: true,
      tipo: 'traspaso',
      filtro: filtroHoy,
      fabrica: databaseFactoryFfi,
    );

    // La base original sigue intacta con sus 2 compras.
    expect(await compras.contarCompras(), 2);
    await db.cerrar();

    final recibido = leerRespaldo(zipBytes);
    expect(recibido.compras, 1);
    expect(recibido.rango, 'Hoy · 25/11/2026');
    expect(recibido.fotos.keys, ['nueva.jpg']);
    expect(recibido.fotos.containsKey('vieja.jpg'), isFalse);

    // Al abrir la base recibida solo está el catalítico del 25/11.
    final dirDest = Directory(p.join(tempDir.path, 'dest'))..createSync(recursive: true);
    final rutaDestDb = p.join(dirDest.path, 'catalog.db');
    await aplicarRespaldo(recibido, rutaBase: rutaDestDb, carpetaBase: dirDest);
    final dbDest = await CatalogDb.abrir(ruta: rutaDestDb, fabrica: databaseFactoryFfi);
    final listaRecibida = await ComprasRepo(dbDest).comprasDelPeriodo(null);
    expect(listaRecibida.single.codigo, hoyCompra.codigo);
    expect(listaRecibida.single.llenado, NivelLlenado.medio);
    await dbDest.cerrar();
  });

  test('v1.7: Lotes de Supervisor guardan observaciones y bloquean repetir catalíticos en otra revisión',
      () async {
    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'sup.db'), fabrica: databaseFactoryFfi);
    addTearDown(db.cerrar);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 14));
    final supervisor = SupervisorRepo(db, reloj: () => DateTime(2026, 11, 25, 15));

    final c1 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 10),
      vendedor: 'Juan Mamani',
      precio: 160000,
      motor: Motor.diesel,
      material: TipoMaterial.dpf,
      llenado: NivelLlenado.fundido,
    ));

    final loteSup = await supervisor.guardarLote(
      nombre: 'Lote Sup. Jorge #1',
      comprador: 'Jorge',
      prefijo: 'CTL',
      rangoTexto: '25/11/2026',
      items: [
        BorradorItemSupervisor(
          codigo: c1.codigo,
          compra: c1,
          escaneadoEn: DateTime(2026, 11, 25, 14, 50),
          observacion: const ObservacionSupervisor(
            tipo: TipoObservacionSupervisor.ceramicaPartida,
            nota: 'Llegó fundido en el centro',
          ),
        ),
      ],
    );

    expect(loteSup.cantidad, 1);
    expect(loteSup.conObservacion, 1);
    expect(loteSup.totalVerificado, 160000);

    final previo = await supervisor.buscarYaRevisado(c1.codigo);
    expect(previo?.loteNombre, 'Lote Sup. Jorge #1');

    // Intentar guardar el mismo código en un segundo lote de supervisor debe fallar.
    await expectLater(
      supervisor.guardarLote(
        nombre: 'Lote Sup. Jorge #2',
        items: [BorradorItemSupervisor(codigo: c1.codigo, compra: c1)],
      ),
      throwsA(isA<DatosInvalidos>()),
    );
  });

  test('v1.7: Excel incorpora logo PNG de CataLog, ExcelTable, Tablas Dinámicas y observaciones en rojo',
      () async {
    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'xl.db'), fabrica: databaseFactoryFfi);
    addTearDown(db.cerrar);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 16));

    final c1 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 11),
      vendedor: 'Taller Rojas',
      precio: 180000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
      llenado: NivelLlenado.entero,
    ));
    final c2 = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 12),
      vendedor: 'Juan Mamani',
      precio: 120000,
      motor: Motor.bencinero,
      material: TipoMaterial.metalico,
      llenado: NivelLlenado.fundido,
    ));

    // 1. Excel de Reporte
    final repBytes = excelDeReporte(Reporte.de([c1, c2], titulo: 'Hoy'), comprador: 'Jorge');
    final libroRep = Excel.decodeBytes(repBytes);
    expect(libroRep.tables.keys, containsAll(['Resumen', 'Compras', 'Tabla Dinámica']));
    expect(libroRep['Resumen'].images, isNotEmpty);
    expect(libroRep['Compras'].tables, isNotEmpty);
    expect(libroRep['Tabla Dinámica'].pivotTables.length, 2);

    // 2. Excel de Revisión de Supervisor con observación destacada en rojo
    final supBytes = excelDeRevisionSupervisor(
      [
        FilaRevisionExcel(
          codigo: c1.codigo,
          compra: c1,
          escaneadoEn: DateTime(2026, 11, 25, 15),
        ),
        FilaRevisionExcel(
          codigo: c2.codigo,
          compra: c2,
          escaneadoEn: DateTime(2026, 11, 25, 15, 5),
          observacion: const ObservacionSupervisor(
            tipo: TipoObservacionSupervisor.ceramicaPartida,
            nota: 'Cerámica rota',
          ),
        ),
      ],
      comprador: 'Jorge',
      prefijo: 'CTL',
      rangoFechas: '25/11/2026',
    );
    final libroSup = Excel.decodeBytes(supBytes);
    expect(libroSup.tables.keys, containsAll(['Revisión', 'Tabla Dinámica']));
    expect(libroSup['Revisión'].images, isNotEmpty);
    expect(libroSup['Revisión'].tables, isNotEmpty);
    expect(libroSup['Tabla Dinámica'].pivotTables.length, 2);
  });

  test('v1.7.1: escaneo de Etiqueta Maestra de Saco (QR y Code 128) resuelve lotes de comprador y supervisor',
      () async {
    final datosSaco = DatosEtiquetaLote(
      codigoLote: 'LOT-261125-0001',
      nombreLote: 'Saco Bodega Norte',
      fecha: DateTime(2026, 11, 25, 14),
      totalPiezas: 12,
      ceramicos: 7,
      metalicos: 3,
      dpf: 2,
      responsable: 'Jorge · CTL',
    );
    // 1. Por QR completo
    final desdeQr = leerCodigoLoteEscaneado(datosSaco.payloadQr)!;
    expect(desdeQr.codigoLote, 'LOT-261125-0001');
    expect(desdeQr.loteId, 1);
    expect(desdeQr.totalPiezas, 12);
    expect(desdeQr.ceramicos, 7);
    expect(desdeQr.nombreLote, 'Saco Bodega Norte');
    expect(desdeQr.esSupervisor, isFalse);
    // No se confunde con catalítico individual
    expect(leerCodigoEscaneado(datosSaco.payloadQr), isNull);
    expect(leerCodigoEscaneado('LOT2611250001'), isNull);
    expect(leerCodigoEscaneado('SUP-261125-0003'), isNull);

    // 2. Por Code 128 sin guiones
    final desdeBarras = leerCodigoLoteEscaneado('SUP2611250003')!;
    expect(desdeBarras.codigoLote, 'SUP-261125-0003');
    expect(desdeBarras.loteId, 3);
    expect(desdeBarras.esSupervisor, isTrue);

    // 3. Resolución contra Lote de Supervisor guardado
    final db = await CatalogDb.abrir(ruta: p.join(tempDir.path, 'saco_sup.db'), fabrica: databaseFactoryFfi);
    addTearDown(db.cerrar);
    final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 15));
    final sup = SupervisorRepo(db, reloj: () => DateTime(2026, 11, 25, 15));
    final c = await compras.crear(DatosCompra(
      fechaCompra: DateTime(2026, 11, 25, 11),
      vendedor: 'Taller Rojas',
      precio: 150000,
      motor: Motor.bencinero,
      material: TipoMaterial.ceramico,
    ));
    final loteSup = await sup.guardarLote(
      nombre: 'Saco Sup #1',
      comprador: 'Jorge',
      prefijo: 'CTL',
      items: [BorradorItemSupervisor(codigo: c.codigo, compra: c)],
    );
    final scopeDummy = AppScope(
      base: db,
      fotos: FotosStore(tempDir),
      child: const SizedBox.shrink(),
    );
    final ficha = await FichaSacoScreen.resolver(
      scope: scopeDummy,
      escaneado: leerCodigoLoteEscaneado(loteSup.codigoLote)!,
    );
    expect(ficha.loteSupervisor?.nombre, 'Saco Sup #1');
    expect(ficha.itemsSupervisor?.single.codigo, c.codigo);
  });

  testWidgets('v1.7: Etiqueta Maestra QR del Saco y nueva pantalla de Revisión de Supervisor', (tester) async {
    late CatalogDb db;
    late AjustesDispositivo disp;
    late Sesiones sesiones;
    late Directory uiDir;

    await tester.runAsync(() async {
      await _cargarFuentes();
      uiDir = await Directory.systemTemp.createTemp('catalog_v17_ui_');
      db = await CatalogDb.abrir(ruta: p.join(uiDir.path, 'ui.db'), fabrica: databaseFactoryFfi);
      final compras = ComprasRepo(db, reloj: () => DateTime(2026, 11, 25, 14));
      await compras.crear(DatosCompra(
        fechaCompra: DateTime(2026, 11, 25, 13),
        vendedor: 'Taller Hermanos Rojas',
        precio: 150000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
        llenado: NivelLlenado.tresCuartos,
      ));
      disp = await AjustesDispositivo.abrir(uiDir);
      sesiones = Sesiones(uiDir, p.join(uiDir.path, 'ui.db'));

      // Renderizado térmico de Etiqueta Maestra QR de Saco (58 mm y 80 mm)
      final datosSaco = DatosEtiquetaLote(
        codigoLote: 'LOT-261125-0001',
        nombreLote: 'Saco Bodega Norte',
        fecha: DateTime(2026, 11, 25, 14),
        totalPiezas: 12,
        ceramicos: 7,
        metalicos: 3,
        dpf: 2,
        responsable: 'Jorge · CTL',
      );
      final mono58 = await aMonocromo(await renderizarEtiquetaLote(datosSaco, anchoPx: 384));
      expect(mono58.ancho, 384);
      expect(mono58.alto, altoEtiquetaLote.round());
    });

    addTearDown(() async {
      await tester.runAsync(() async {
        await db.cerrar();
        if (await uiDir.exists()) await uiDir.delete(recursive: true);
      });
    });

    Future<void> bombear([int ms = 300]) async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
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

    // 1. Nueva compra muestra los chips de estado de llenado de la cerámica
    await tester.pumpWidget(envolver(const CompraFormScreen()));
    await bombear();
    expect(find.text('Entero 100%', skipOffstage: false), findsOneWidget);
    expect(find.text('Fundido/Partido', skipOffstage: false), findsOneWidget);

    // 2. Revisión de Supervisor rediseñada muestra anillo, Guardar Lote Supervisor, Lotes Supervisor y pastilla 3/4
    await tester.pumpWidget(envolver(const RevisionSupervisorScreen(iniciarConCamara: false)));
    await bombear();
    expect(find.text('Guardar Lote Supervisor'), findsOneWidget);
    expect(find.textContaining('Lotes Supervisor'), findsOneWidget);
    expect(find.text('3/4'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await bombear(100);
  });
}
