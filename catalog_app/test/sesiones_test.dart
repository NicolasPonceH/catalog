import 'dart:io';

import 'package:catalog/backup/auto.dart';
import 'package:catalog/backup/respaldo.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/dispositivo.dart';
import 'package:catalog/data/sesiones.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory otroCelular;
  late Directory miCelular;

  DatosCompra datos(String vendedor) => DatosCompra(
        fechaCompra: DateTime(2026, 11, 21, 9),
        vendedor: vendedor,
        precio: 100000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
      );

  /// Arma el archivo que mandaría el otro celular, con [n] compras.
  Future<ContenidoRespaldo> datosDelOtro(int n, {bool fotos = true}) async {
    final base = await CatalogDb.abrir(ruta: p.join(otroCelular.path, 'catalog.db'), fabrica: databaseFactoryFfi);
    final repo = ComprasRepo(base, reloj: () => DateTime(2026, 11, 21, 10));
    await repo.guardarAjuste('prefijo', 'CTL');
    await repo.guardarAjuste('nombre', 'Papá');
    final actuales = await repo.contarCompras();
    for (var i = actuales; i < n; i++) {
      await repo.crear(datos('Vendedor $i'));
    }
    await Directory(p.join(otroCelular.path, 'fotos')).create(recursive: true);
    await File(p.join(otroCelular.path, 'fotos', '1.jpg')).writeAsBytes([9, 9, 9]);
    final zip = await armarRespaldo(base, otroCelular, incluirFotos: fotos, tipo: 'traspaso');
    await base.cerrar();
    return leerRespaldo(zip);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await initializeDateFormatting('es');
  });

  setUp(() async {
    otroCelular = await Directory.systemTemp.createTemp('catalog_otro_');
    miCelular = await Directory.systemTemp.createTemp('catalog_mio_');
  });

  tearDown(() async {
    await otroCelular.delete(recursive: true);
    await miCelular.delete(recursive: true);
  });

  test('los datos recibidos quedan en una sesión de revisión aparte', () async {
    final sesiones = Sesiones(miCelular, p.join(miCelular.path, 'catalog.db'));
    // Mis propias compras.
    final mia = await CatalogDb.abrir(ruta: sesiones.principal.rutaBase, fabrica: databaseFactoryFfi);
    await ComprasRepo(mia).guardarAjuste('prefijo', 'CTT');
    await ComprasRepo(mia).crear(datos('Mi vendedor'));
    await mia.cerrar();

    final recibido = await datosDelOtro(3);
    final revision = await sesiones.guardarRevision(recibido, ahora: DateTime(2026, 11, 22, 12));
    expect(revision.esRevision, isTrue);
    expect(revision.nombre, 'Revisión de Papá');
    expect(revision.compras, 3);
    expect(revision.prefijo, 'CTL');

    // La revisión tiene las 3 compras del otro y su foto…
    final base = await CatalogDb.abrir(ruta: revision.rutaBase, fabrica: databaseFactoryFfi);
    expect(await ComprasRepo(base).contarCompras(), 3);
    expect(await ComprasRepo(base).buscarPorCodigo('CTL-261121-0001'), isNotNull);
    await base.cerrar();
    expect(File(p.join(revision.carpeta.path, 'fotos', '1.jpg')).existsSync(), isTrue);

    // …y mis compras siguen intactas.
    final mia2 = await CatalogDb.abrir(ruta: sesiones.principal.rutaBase, fabrica: databaseFactoryFfi);
    expect(await ComprasRepo(mia2).contarCompras(), 1);
    expect(await ComprasRepo(mia2).buscarPorCodigo('CTL-261121-0001'), isNull);
    await mia2.cerrar();

    expect((await sesiones.revisiones()).single.id, revision.id);
    expect((await sesiones.buscar(revision.id))!.nombre, 'Revisión de Papá');
    expect((await sesiones.buscar(null))!.id, idSesionPrincipal);
  });

  test('recibir otra vez del mismo teléfono actualiza esa revisión', () async {
    final sesiones = Sesiones(miCelular, p.join(miCelular.path, 'catalog.db'));
    final primera = await sesiones.guardarRevision(await datosDelOtro(2), ahora: DateTime(2026, 11, 22, 9));
    final segunda = await sesiones.guardarRevision(await datosDelOtro(5), ahora: DateTime(2026, 11, 23, 9));
    expect(segunda.id, primera.id);
    expect(segunda.compras, 5);
    expect((await sesiones.revisiones()).length, 1);

    await sesiones.eliminar(segunda);
    expect(await sesiones.revisiones(), isEmpty);
    await sesiones.eliminar(sesiones.principal); // la sesión de compra nunca se borra
  });

  test('se puede enviar sin fotos para que pese menos', () async {
    final sinFotos = await datosDelOtro(1, fotos: false);
    expect(sinFotos.fotos, isEmpty);
    expect(sinFotos.manifiesto['tipo'], 'traspaso');
  });

  test('los ajustes del teléfono se guardan aparte y se migra la impresora', () async {
    final d = await AjustesDispositivo.abrir(miCelular);
    expect(d.leer(AjustesDispositivo.impresora), isNull);

    final base = await CatalogDb.abrir(ruta: p.join(miCelular.path, 'catalog.db'), fabrica: databaseFactoryFfi);
    await ComprasRepo(base).guardarAjuste('impresora', '{"id":"AA"}');
    await d.migrarDesde(ComprasRepo(base));
    await base.cerrar();
    expect(d.leer(AjustesDispositivo.impresora), '{"id":"AA"}');

    await d.guardar(AjustesDispositivo.bloqueo, '1');
    final releido = await AjustesDispositivo.abrir(miCelular);
    expect(releido.activado(AjustesDispositivo.bloqueo), isTrue);
    expect(releido.leer(AjustesDispositivo.impresora), '{"id":"AA"}');
  });

  test('el respaldo automático se hace una vez por día', () {
    final hoy = DateTime(2026, 11, 22, 18);
    expect(tocaRespaldoAutomatico(null, hoy), isTrue);
    expect(tocaRespaldoAutomatico(DateTime(2026, 11, 22, 8), hoy), isFalse);
    expect(tocaRespaldoAutomatico(DateTime(2026, 11, 21, 23, 59), hoy), isTrue);
    expect(nombreAutoRespaldo('CTL', hoy), 'CataLog-auto-CTL-20261122.zip');
  });
}
