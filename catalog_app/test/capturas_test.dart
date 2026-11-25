// Capturas de pantalla para el README, con datos de ejemplo (nunca datos reales).
//
//   flutter test test/capturas_test.dart --dart-define=CAPTURAS=true
//
// Deja los PNG en build/capturas/. Sin el --dart-define la prueba se salta.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog/app_scope.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/data/supervisor_repo.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/presentacion_screen.dart';
import 'package:catalog/features/revision_supervisor_screen.dart';
import 'package:catalog/i18n.dart';
import 'package:catalog/main.dart';
import 'package:catalog/printing/etiqueta.dart';
import 'package:catalog/printing/raster.dart';
import 'package:catalog/theme.dart';
import 'package:catalog/widgets/catalog_logo.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _activo = bool.fromEnvironment('CAPTURAS');

// Pantalla de un Android común: 1080 x 2340 a 2,75 puntos por dp.
const _dpr = 2.75;
const _fisico = Size(1080, 2340);
const _barraEstado = 28.0; // dp

final _raiz = GlobalKey();
final _salida = Directory('build/capturas');

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
  // Íconos de Material: vienen con Flutter (bin/cache/artifacts/material_fonts).
  final candidatos = [
    if (Platform.environment['FLUTTER_ROOT'] case final raiz?)
      '$raiz/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/materialicons-regular.otf',
  ];
  final iconos = candidatos.map(File.new).where((f) => f.existsSync()).firstOrNull;
  if (iconos == null) throw StateError('No encontré materialicons-regular.otf en $candidatos');
  final loader = FontLoader('MaterialIcons')..addFont(iconos.readAsBytes().then((b) => ByteData.view(b.buffer)));
  await loader.load();
}

/// Compras inventadas en Arica: vendedores, lugares y autos de ejemplo.
Future<List<Compra>> _poblar(CatalogDb base, DateTime ahora) async {
  final compras = ComprasRepo(base);
  await compras.guardarAjuste('prefijo', 'CTL');
  await compras.guardarAjuste('nombre', 'Jorge Ramírez');

  final ayer = DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(days: 1));
  DateTime dia(int diasAtras, int h, int m) =>
      DateTime(ayer.year, ayer.month, ayer.day - diasAtras, h, m);

  final datos = <DatosCompra>[
    // Del mes pasado (para que el reporte muestre más de un mes).
    DatosCompra(fechaCompra: dia(30, 11, 5), vendedor: 'Desarmaduría El Morro', lugar: 'Panamericana Norte',
        precio: 95000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: '1ZZ-01', autos: 'Toyota Corolla 2009', lat: -18.4521, lng: -70.2938),
    DatosCompra(fechaCompra: dia(27, 16, 40), vendedor: 'Pedro Contreras', lugar: 'Valle de Azapa km 7',
        precio: 160000, motor: Motor.diesel, material: TipoMaterial.dpf,
        codigoFabrica: 'DPF 2KD', autos: 'Toyota Hilux 2.5 D-4D', lat: -18.5180, lng: -70.1810),
    // De este mes.
    DatosCompra(fechaCompra: dia(9, 10, 20), vendedor: 'Taller Hermanos Rojas', lugar: 'Av. Santa María',
        precio: 70000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: 'K4M 2D', autos: 'Renault Symbol 2013', lat: -18.4746, lng: -70.3002),
    DatosCompra(fechaCompra: dia(8, 12, 45), vendedor: 'Lubricentro Azapa', lugar: 'Valle de Azapa km 3',
        precio: 45000, motor: Motor.bencinero, material: TipoMaterial.metalico,
        codigoFabrica: 'MET 118', autos: 'Kia Morning 2015', lat: -18.5021, lng: -70.2585),
    DatosCompra(fechaCompra: dia(6, 9, 30), vendedor: 'Juan Mamani', lugar: 'Terminal Agropecuario',
        precio: 180000, motor: Motor.diesel, material: TipoMaterial.dpf,
        codigoFabrica: 'YD25 DPF', autos: 'Nissan Navara D40', lat: -18.4930, lng: -70.2894),
    DatosCompra(fechaCompra: dia(5, 17, 15), vendedor: 'Taller Hermanos Rojas', lugar: 'Av. Santa María',
        precio: 60000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: '0D140', autos: 'Toyota Yaris 2012', lat: -18.4746, lng: -70.3002),
    DatosCompra(fechaCompra: dia(4, 11, 0), vendedor: 'Automotora Chinchorro', lugar: 'Chinchorro',
        precio: 85000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: 'G4FC 21', autos: 'Hyundai Accent 2012', lat: -18.4590, lng: -70.3050),
    DatosCompra(fechaCompra: dia(3, 15, 50), vendedor: 'Desarmaduría El Morro', lugar: 'Panamericana Norte',
        precio: 120000, motor: Motor.diesel, material: TipoMaterial.metalico,
        codigoFabrica: '4D56 MT', autos: 'Mitsubishi L200 2010', lat: -18.4521, lng: -70.2938),
    DatosCompra(fechaCompra: dia(2, 10, 10), vendedor: 'Pedro Contreras', lugar: 'Valle de Azapa km 7',
        precio: 55000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: 'B12D1', autos: 'Chevrolet Sail 2016', lat: -18.5180, lng: -70.1810),
    DatosCompra(fechaCompra: dia(1, 18, 25), vendedor: 'Juan Mamani', lugar: 'Terminal Agropecuario',
        precio: 150000, motor: Motor.diesel, material: TipoMaterial.dpf,
        codigoFabrica: '1KD DPF', autos: 'Toyota Hilux 3.0 D-4D', lat: -18.4930, lng: -70.2894),
    DatosCompra(fechaCompra: dia(0, 11, 40), vendedor: 'Lubricentro Azapa', lugar: 'Valle de Azapa km 3',
        precio: 40000, motor: Motor.bencinero, material: TipoMaterial.metalico, llenado: NivelLlenado.tresCuartos,
        codigoFabrica: 'M13A', autos: 'Suzuki Swift 2013', lat: -18.5021, lng: -70.2585),
    DatosCompra(fechaCompra: dia(0, 16, 5), vendedor: 'Taller Hermanos Rojas', lugar: 'Av. Santa María',
        precio: 75000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: '2NZ 07', autos: 'Toyota Yaris 2014', lat: -18.4746, lng: -70.3002),
  ];

  final creadas = <Compra>[];
  for (var i = 0; i < datos.length; i++) {
    final c = await compras.crear(datos[i]);
    // Deja la penúltima sin imprimir para que el chip "Sin imprimir (1)" luzca en Historial.
    if (i != datos.length - 2) await compras.marcarImpresion(c.id);
    creadas.add(c);
  }
  await compras.registrarRespaldo();

  final lotes = LotesRepo(base);
  final entrega = await lotes.crear(nombre: 'Entrega a fundición');
  for (final c in creadas.skip(2).take(6)) {
    await lotes.agregarEscaneado(entrega.id, c.codigo);
  }
  await lotes.cerrar(entrega.id, montoRecibido: 720000, actualizarMonto: true);
  final revision = await lotes.crear(nombre: 'Revisión de bodega');
  for (final c in creadas.skip(8)) {
    await lotes.agregarEscaneado(revision.id, c.codigo);
  }
  return creadas;
}

/// Deja terminar las consultas a la base (async real) y las animaciones.
Future<void> _esperar(WidgetTester t) async {
  for (var i = 0; i < 3; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    for (var j = 0; j < 4; j++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }
}

Future<void> _capturar(WidgetTester t, String nombre, {bool esperar = true}) async {
  if (esperar) await _esperar(t);
  final ro = t.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
  await t.runAsync(() async {
    final img = await ro.toImage(pixelRatio: _dpr);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('${_salida.path}/$nombre.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _volver(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await _esperar(t);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
    await initializeDateFormatting('en');
  });

  testWidgets('capturas para el README', skip: !_activo, (tester) async {
    tester.view.physicalSize = _fisico;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: _barraEstado * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: _barraEstado * _dpr);
    addTearDown(tester.view.reset);
    // Como en un teléfono táctil: sin el borde de foco del teclado.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    // Las pruebas cambian las sombras por un borde negro; aquí se quieren sombras reales.
    debugDisableShadows = false;

    // GPS de ejemplo (en las pruebas no hay GPS): centro de Arica.
    const gps = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(gps, (llamada) async {
      return switch (llamada.method) {
        'isLocationServiceEnabled' => true,
        'checkPermission' || 'requestPermission' => 2, // whileInUse
        'getCurrentPosition' || 'getLastKnownPosition' => {
            'latitude': -18.4746,
            'longitude': -70.3002,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'accuracy': 6.0,
            'altitude': 20.0,
            'altitude_accuracy': 3.0,
            'heading': 0.0,
            'heading_accuracy': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
            'is_mocked': false,
          },
        _ => null,
      };
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(gps, null));

    late CatalogDb base;
    late List<Compra> compras;
    await tester.runAsync(() async {
      _salida.createSync(recursive: true);
      await _cargarFuentes();
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      compras = await _poblar(base, DateTime.now());

      // El sticker tal como sale en la impresora (blanco y negro, 80 mm).
      final ultima = compras.last;
      final mono = await aMonocromo(await renderizarEtiqueta(DatosEtiqueta.deCompra(ultima), anchoPx: 576));
      File('${_salida.path}/sticker.png').writeAsBytesSync(await pngDeMonocromo(mono));
    });

    // Bienvenida animada: se captura cuando terminó de armarse, antes de entrar.
    var bienvenida = true;
    await tester.pumpWidget(RepaintBoundary(
      key: _raiz,
      child: AppScope(
        base: base,
        fotos: FotosStore(Directory.systemTemp),
        child: StatefulBuilder(
          builder: (context, setState) => CatalogApp(
            bienvenida: bienvenida,
            alEntrar: () => setState(() => bienvenida = false),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    for (var i = 0; i < 29; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capturar(tester, '8-bienvenida', esperar: false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(bienvenida, isFalse);

    await _capturar(tester, '1-inicio');

    // Guía del Inicio (botón de ayuda), en el segundo paso.
    await tester.tap(find.byTooltip('Ayuda: guía de esta pantalla'));
    await _esperar(tester);
    await tester.tap(find.text('Siguiente'));
    await _capturar(tester, '10-guia');
    await tester.tap(find.byTooltip('Salir de la guía'));
    await _esperar(tester);

    // Presentación: la página del sticker (a mitad de la animación) y la última.
    final navegador = tester.state<NavigatorState>(find.byType(Navigator).first);
    unawaited(abrirPresentacion(navegador));
    await _esperar(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Siguiente'));
      await _esperar(tester);
    }
    await _capturar(tester, '9-presentacion');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Siguiente'));
      await _esperar(tester);
    }
    await tester.enterText(find.byType(TextField).first, 'Jorge Ramírez');
    FocusManager.instance.primaryFocus?.unfocus();
    await _capturar(tester, '9-presentacion-final');
    await _volver(tester);

    // Respaldo y traspaso (botón de flechas).
    await tester.tap(find.byTooltip('Respaldo y traspaso'));
    await _capturar(tester, '7-respaldo');
    await _volver(tester);

    // Ficha de la compra más nueva, con su sticker.
    await tester.tap(find.text(compras.last.codigo));
    await _capturar(tester, '3-ficha');
    await _volver(tester);

    // Nueva compra, con datos escritos y código de fábrica para mostrar la pastilla de referencia.
    await tester.tap(find.text('Nueva compra'));
    await _esperar(tester);
    final campos = find.byType(EditableText);
    await tester.enterText(campos.at(0), 'Taller Hermanos Rojas');
    await tester.enterText(campos.at(1), 'Av. Santa María');
    await tester.enterText(campos.at(2), '65000');
    await tester.tap(find.text('Bencinero'));
    await tester.tap(find.text('Cerámico'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await _esperar(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Código grabado de fábrica'), '0D140');
    FocusManager.instance.primaryFocus?.unfocus();
    await _capturar(tester, '2-nueva-compra');
    await _volver(tester);

    // Pestañas de la barra de abajo.
    await tester.tap(find.text('Historial'));
    await _capturar(tester, '4-historial');

    await tester.tap(find.text('Reportes'));
    await _capturar(tester, '5-reportes');

    await tester.tap(find.text('Lotes'));
    await _capturar(tester, '6-lotes');

    await tester.tap(find.text('Inicio'));
    await _esperar(tester);

    // Módulo operativo de Revisión de Supervisor v1.7 (con anillo, fechas, observación y Lote Supervisor).
    await tester.runAsync(() async {
      await SupervisorRepo(base).guardarLote(
        nombre: 'Lote Sup. Jorge #1',
        comprador: 'Jorge Ramírez',
        prefijo: 'CTL',
        rangoTexto: 'Mes anterior',
        items: [
          for (final c in compras.take(2))
            BorradorItemSupervisor(codigo: c.codigo, compra: c, escaneadoEn: DateTime.now()),
        ],
      );
      final verif = File('${Directory.systemTemp.path}/verificados_supervisor_local_v2.json');
      final ahoraMs = DateTime.now().millisecondsSinceEpoch;
      final esc = {
        for (final c in compras.skip(5)) '"${c.codigo}":$ahoraMs',
      }.join(',');
      final codObs = compras[compras.length - 2].codigo;
      await verif.writeAsString(
        '{"escaneados":{$esc},"observaciones":{"$codObs":{"tipo":"ceramica_partida","nota":"Cerámica 3/4 con fisura"}}}',
        flush: true,
      );
    });
    navegador.push(MaterialPageRoute(builder: (_) => const RevisionSupervisorScreen(iniciarConCamara: false)));
    await _capturar(tester, '18-supervisor');
    await _volver(tester);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.runAsync(base.cerrar);
    debugDisableShadows = true;
  });

  for (final (sufijo, paleta) in [('', Paleta.clara), ('-oscuro', Paleta.oscura_)]) {
    testWidgets('capturas del tema$sufijo', skip: !_activo, (tester) async {
      tester.view.physicalSize = _fisico;
      tester.view.devicePixelRatio = _dpr;
      tester.view.padding = const FakeViewPadding(top: _barraEstado * _dpr);
      tester.view.viewPadding = const FakeViewPadding(top: _barraEstado * _dpr);
      addTearDown(tester.view.reset);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      debugDisableShadows = false;
      CatalogColors.paleta = paleta;
      addTearDown(() => CatalogColors.paleta = Paleta.clara);
      late CatalogDb base;
      await tester.runAsync(() async {
        _salida.createSync(recursive: true);
        await _cargarFuentes();
        base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
        await _poblar(base, DateTime.now());
      });
      await tester.pumpWidget(RepaintBoundary(
        key: _raiz,
        child: AppScope(base: base, fotos: FotosStore(Directory.systemTemp), child: CatalogApp(paleta: paleta)),
      ));
      await _capturar(tester, '12-inicio$sufijo');
      await tester.tap(find.byTooltip('Ajustes'));
      await _capturar(tester, '13-ajustes$sufijo');
      if (sufijo.isEmpty) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -680));
        await _capturar(tester, '16-ajustes-notificaciones');
        await tester.drag(find.byType(ListView).last, const Offset(0, -620));
        await _capturar(tester, '17-ajustes-ubicar-respaldo');
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.runAsync(base.cerrar);
      debugDisableShadows = true;
    });
  }

  testWidgets('captura del bloqueo con huella', skip: !_activo, (tester) async {
    tester.view.physicalSize = _fisico;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: _barraEstado * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: _barraEstado * _dpr);
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    late CatalogDb base;
    await tester.runAsync(() async {
      _salida.createSync(recursive: true);
      await _cargarFuentes();
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      await ComprasRepo(base).guardarAjuste('nombre', 'Jorge Ramírez');
    });
    await tester.pumpWidget(RepaintBoundary(
      key: _raiz,
      child: AppScope(
        base: base,
        fotos: FotosStore(Directory.systemTemp),
        child: const CatalogApp(bloqueada: true),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    // Entrada (1,3 s) y un momento analizando la huella.
    for (var i = 0; i < 21; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capturar(tester, '11-bloqueo', esperar: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(base.cerrar);
    debugDisableShadows = true;
  });

  testWidgets('capturas en inglés', skip: !_activo, (tester) async {
    tester.view.physicalSize = _fisico;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: _barraEstado * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: _barraEstado * _dpr);
    addTearDown(tester.view.reset);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    debugDisableShadows = false;
    addTearDown(() => Idioma.actual = 'es');
    late CatalogDb base;
    await tester.runAsync(() async {
      _salida.createSync(recursive: true);
      await _cargarFuentes();
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
      await _poblar(base, DateTime.now());
    });
    await tester.pumpWidget(RepaintBoundary(
      key: _raiz,
      child: AppScope(base: base, fotos: FotosStore(Directory.systemTemp), child: const CatalogApp(idioma: 'en')),
    ));
    await _capturar(tester, '14-inicio-en');
    await tester.tap(find.byTooltip('Settings'));
    await _capturar(tester, '15-ajustes-en');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.runAsync(base.cerrar);
    debugDisableShadows = true;
  });

  testWidgets('portada del README con pantallas actualizadas', skip: !_activo, (tester) async {
    const tamano = Size(1600, 900);
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;

    late ui.Image imgFicha;
    late ui.Image imgInicio;
    late ui.Image imgReportes;
    await tester.runAsync(() async {
      await _cargarFuentes();
      Future<ui.Image> leer(String n) async {
        final bytes = await File('${_salida.path}/$n.png').readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        return (await codec.getNextFrame()).image;
      }

      imgFicha = await leer('3-ficha');
      imgInicio = await leer('1-inicio');
      imgReportes = await leer('5-reportes');
    });

    Widget marcoTelefono(ui.Image captura, {required double ancho, bool frente = false}) {
      final alto = ancho * (2340 / 1080);
      return Container(
        width: ancho + 18,
        height: alto + 18,
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: const Color(0xFF0A141F),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: const Color(0xFF2B4159), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: frente ? 0.55 : 0.38),
              blurRadius: frente ? 44 : 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: RawImage(image: captura, fit: BoxFit.cover),
        ),
      );
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _raiz,
          child: Container(
            width: 1600,
            height: 900,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.45, -0.35),
                radius: 1.35,
                colors: [Color(0xFF173A5E), Color(0xFF0E2A47), Color(0xFF08192B)],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 96,
                  top: 205,
                  width: 710,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CatalogLogo(altura: 86, oscuro: true),
                      const SizedBox(height: 54),
                      const Text(
                        'Control de compras\nde catalíticos',
                        style: TextStyle(
                          fontFamily: fuenteUi,
                          fontSize: 54,
                          fontWeight: FontWeight.w700,
                          height: 1.12,
                          color: CatalogColors.niebla,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Registra cada compra, imprime un sticker con QR, escanéalo\ny saca reportes en Excel. Funciona sin internet.',
                        style: TextStyle(
                          fontFamily: fuenteUi,
                          fontSize: 21,
                          height: 1.44,
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 36),
                      const Text(
                        'FLUTTER · ANDROID · WI-FI LOCAL · BLUETOOTH · ES / EN',
                        style: TextStyle(
                          fontFamily: fuenteMono,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.0,
                          color: CatalogColors.naranja,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(left: 855, top: 205, child: marcoTelefono(imgFicha, ancho: 250)),
                Positioned(left: 1245, top: 205, child: marcoTelefono(imgReportes, ancho: 250)),
                Positioned(left: 1030, top: 132, child: marcoTelefono(imgInicio, ancho: 292, frente: true)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final ro = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    await tester.runAsync(() async {
      final img = await ro.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('${_salida.path}/portada.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    debugDisableShadows = true;
  });
}
