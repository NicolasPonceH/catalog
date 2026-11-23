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
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/features/presentacion_screen.dart';
import 'package:catalog/main.dart';
import 'package:catalog/printing/etiqueta.dart';
import 'package:catalog/printing/raster.dart';
import 'package:catalog/theme.dart';
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
        precio: 40000, motor: Motor.bencinero, material: TipoMaterial.metalico,
        codigoFabrica: 'M13A', autos: 'Suzuki Swift 2013', lat: -18.5021, lng: -70.2585),
    DatosCompra(fechaCompra: dia(0, 16, 5), vendedor: 'Taller Hermanos Rojas', lugar: 'Av. Santa María',
        precio: 75000, motor: Motor.bencinero, material: TipoMaterial.ceramico,
        codigoFabrica: '2NZ 07', autos: 'Toyota Yaris 2014', lat: -18.4746, lng: -70.3002),
  ];

  final creadas = <Compra>[];
  for (final d in datos) {
    final c = await compras.crear(d);
    await compras.marcarImpresion(c.id);
    creadas.add(c);
  }
  await compras.registrarRespaldo();

  final lotes = LotesRepo(base);
  final entrega = await lotes.crear(nombre: 'Entrega a fundición');
  for (final c in creadas.skip(2).take(6)) {
    await lotes.agregarEscaneado(entrega.id, c.codigo);
  }
  await lotes.cerrar(entrega.id);
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

    // Nueva compra, con algunos datos escritos.
    await tester.tap(find.text('Nueva compra'));
    await _esperar(tester);
    final campos = find.byType(EditableText);
    await tester.enterText(campos.at(0), 'Taller Hermanos Rojas');
    await tester.enterText(campos.at(1), 'Av. Santa María');
    await tester.enterText(campos.at(2), '75000');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.tap(find.text('Bencinero'));
    await tester.tap(find.text('Cerámico'));
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
}
