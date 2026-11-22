import 'dart:io';

import 'package:archive/archive.dart';
import 'package:catalog/backup/respaldo.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory carpeta;
  late CatalogDb base;
  var reloj = DateTime(2026, 11, 21, 10);

  DatosCompra datos({String vendedor = 'Juan', String? foto}) => DatosCompra(
        fechaCompra: DateTime(2026, 11, 21, 9),
        vendedor: vendedor,
        precio: 180000,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
        fotoPath: foto,
      );

  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  setUp(() async {
    reloj = DateTime(2026, 11, 21, 10);
    carpeta = await Directory.systemTemp.createTemp('catalog_respaldo_');
    base = await CatalogDb.abrir(ruta: p.join(carpeta.path, 'catalog.db'), fabrica: databaseFactoryFfi);
  });

  tearDown(() async {
    try {
      await base.cerrar();
    } catch (_) {}
    await carpeta.delete(recursive: true);
  });

  test('respaldar y restaurar en otro teléfono deja las mismas compras y fotos', () async {
    final repo = ComprasRepo(base, reloj: () => reloj);
    await repo.guardarAjuste('prefijo', 'CTT');
    await Directory(p.join(carpeta.path, 'fotos')).create();
    await File(p.join(carpeta.path, 'fotos', '111.jpg')).writeAsBytes([1, 2, 3, 4]);
    final a = await repo.crear(datos(vendedor: 'Ana', foto: 'fotos/111.jpg'));
    await repo.crear(datos(vendedor: 'Beto'));

    final zip = await armarRespaldo(base, carpeta, ahora: DateTime(2026, 11, 21, 18));
    final contenido = leerRespaldo(zip);
    expect(contenido.compras, 2);
    expect(contenido.prefijo, 'CTT');
    expect(contenido.creado, DateTime(2026, 11, 21, 18));
    expect(contenido.fotos.keys, ['111.jpg']);

    // "Otro teléfono": carpeta nueva y vacía.
    final otro = await Directory.systemTemp.createTemp('catalog_otro_');
    try {
      final ruta = p.join(otro.path, 'catalog.db');
      await aplicarRespaldo(contenido, rutaBase: ruta, carpetaBase: otro);
      final restaurada = await CatalogDb.abrir(ruta: ruta, fabrica: databaseFactoryFfi);
      final repo2 = ComprasRepo(restaurada);
      expect(await repo2.contarCompras(), 2);
      final ana = await repo2.buscarPorCodigo(a.codigo);
      expect(ana!.vendedor, 'Ana');
      expect(ana.fechaCompra, DateTime(2026, 11, 21, 9));
      expect(await repo2.prefijo(), 'CTT');
      expect(await File(p.join(otro.path, ana.fotoPath!)).readAsBytes(), [1, 2, 3, 4]);
      // Se pueden seguir registrando compras sin repetir números.
      final nueva = await repo2.crear(datos());
      expect(nueva.codigo, 'CTT-261121-0003');
      await restaurada.cerrar();
    } finally {
      await otro.delete(recursive: true);
    }
  });

  test('rechaza archivos que no son respaldos de CataLog', () {
    expect(() => leerRespaldo([1, 2, 3]), throwsA(isA<RespaldoInvalido>()));
    final zipAjeno = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('hola.txt', 'hola')));
    expect(() => leerRespaldo(zipAjeno), throwsA(isA<RespaldoInvalido>()));
  });

  test('la copia antes de restaurar conserva solo las 3 últimas', () async {
    for (var i = 0; i < 5; i++) {
      await guardarCopiaLocal(await armarRespaldo(base, carpeta), carpeta, ahora: DateTime(2026, 11, 21, 10, i));
    }
    final copias = Directory(p.join(carpeta.path, 'respaldos')).listSync();
    expect(copias.length, 3);
  });

  test('el recordatorio aparece cuando hace falta respaldar', () async {
    final repo = ComprasRepo(base, reloj: () => reloj);
    expect(await repo.avisoRespaldo(), isNull, reason: 'sin compras no hay nada que respaldar');

    await repo.crear(datos());
    expect(await repo.avisoRespaldo(), isNull, reason: 'recién registrada');

    reloj = DateTime(2026, 11, 22, 12);
    expect(await repo.avisoRespaldo(), contains('Todavía no has hecho un respaldo'));

    await repo.registrarRespaldo();
    expect(await repo.avisoRespaldo(), isNull, reason: 'recién respaldado');

    reloj = DateTime(2026, 11, 23, 9);
    await repo.crear(datos());
    expect(await repo.avisoRespaldo(), isNull, reason: 'una compra nueva y pasó solo un día');

    reloj = DateTime(2026, 11, 30, 9);
    expect(await repo.avisoRespaldo(), contains('Hace 7 días'));
  });
}
