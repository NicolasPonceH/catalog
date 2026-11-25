import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/base.dart';
import '../data/compra.dart';
import '../data/migraciones.dart';

// Respaldo y traspaso filtrado: un .zip con la base de datos, las fotos y un manifiesto.
// Sirve para respaldar todo o para sincronizar por WhatsApp / Wi-Fi solo ciertas fechas.

const archivoManifiesto = 'manifiesto.json';
const archivoBase = 'catalog.db';
const versionRespaldo = 1;

class RespaldoInvalido implements Exception {
  RespaldoInvalido(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Filtro opcional por fechas de compra o estado de lote al enviar datos a otro celular.
class FiltroEnvioCatalog {
  const FiltroEnvioCatalog({
    this.desde,
    this.hastaExclusivo,
    this.soloSinLote = false,
    this.etiqueta = '',
  });

  static const todo = FiltroEnvioCatalog();

  final DateTime? desde;
  final DateTime? hastaExclusivo;
  final bool soloSinLote;
  final String etiqueta;

  bool get tieneFiltro => desde != null || hastaExclusivo != null || soloSinLote;

  (String?, List<Object?>) clausulaWhere() {
    final partes = <String>[];
    final args = <Object?>[];
    if (desde != null) {
      partes.add('fecha_compra >= ?');
      args.add(ms(desde!));
    }
    if (hastaExclusivo != null) {
      partes.add('fecha_compra < ?');
      args.add(ms(hastaExclusivo!));
    }
    if (soloSinLote) {
      partes.add('id NOT IN (SELECT compra_id FROM lote_items)');
    }
    return (partes.isEmpty ? null : partes.join(' AND '), args);
  }
}

/// Cuenta cuántas compras (y qué monto activo) entran en [filtro].
Future<(int cantidad, int montoActivo)> contarComprasParaEnvio(
  CatalogDb base,
  FiltroEnvioCatalog filtro,
) async {
  final (where, args) = filtro.clausulaWhere();
  final sql = 'SELECT COUNT(*) AS n, '
      "COALESCE(SUM(CASE WHEN estado = 'activa' THEN precio ELSE 0 END), 0) AS t "
      'FROM compras${where != null ? ' WHERE $where' : ''}';
  final filas = await base.db.rawQuery(sql, args);
  final n = (filas.first['n'] as num?)?.toInt() ?? 0;
  final t = (filas.first['t'] as num?)?.toInt() ?? 0;
  return (n, t);
}

class ContenidoRespaldo {
  ContenidoRespaldo(this.manifiesto, this.base, this.fotos);

  final Map<String, dynamic> manifiesto;
  final Uint8List base;
  final Map<String, Uint8List> fotos;

  int get compras => (manifiesto['compras'] as num?)?.toInt() ?? 0;
  DateTime? get creado => DateTime.tryParse(manifiesto['creado'] as String? ?? '');
  String get prefijo => manifiesto['prefijo'] as String? ?? '';
  String get nombre => manifiesto['nombre'] as String? ?? '';
  String get rango => manifiesto['rango'] as String? ?? '';
}

Future<String?> _ajuste(Database db, String clave) async {
  final filas = await db.query('ajustes', where: 'clave = ?', whereArgs: [clave]);
  return filas.isEmpty ? null : filas.first['valor'] as String?;
}

/// Arma el .zip con la base de datos y (si se pide) las fotos.
/// Si se pasa [filtro] con fechas o `soloSinLote`, recorta una copia temporal de
/// la base para enviar únicamente esas compras y sus fotos (sin tocar la base real).
Future<Uint8List> armarRespaldo(
  CatalogDb base,
  Directory carpetaBase, {
  DateTime? ahora,
  bool incluirFotos = true,
  String tipo = 'respaldo',
  FiltroEnvioCatalog? filtro,
  DatabaseFactory? fabrica,
}) async {
  final db = base.db;
  try {
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}

  Uint8List bytesBase;
  int compras;
  Set<String>? fotosPermitidas;

  if (filtro == null || !filtro.tieneFiltro) {
    bytesBase = await File(db.path).readAsBytes();
    compras = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM compras')) ?? 0;
  } else {
    final tempDir = await Directory.systemTemp.createTemp('catalog_envio_');
    try {
      final rutaTemp = p.join(tempDir.path, 'filtrado.db');
      await File(db.path).copy(rutaTemp);
      final f = fabrica ?? databaseFactory;
      final tempDb = await f.openDatabase(rutaTemp);
      try {
        await tempDb.execute('PRAGMA foreign_keys = OFF');
        final (where, args) = filtro.clausulaWhere();
        final elegidas = await tempDb.query(
          'compras',
          columns: ['id', 'foto_path'],
          where: where,
          whereArgs: args.isEmpty ? null : args,
        );
        final ids = [for (final r in elegidas) r['id']! as int];
        fotosPermitidas = {
          for (final r in elegidas)
            if ((r['foto_path'] as String?)?.trim().isNotEmpty == true)
              p.basename((r['foto_path']! as String).trim()),
        };
        if (ids.isEmpty) {
          await tempDb.delete('lote_items');
          await tempDb.delete('lotes');
          await tempDb.delete('compras');
        } else {
          final listaIds = ids.join(',');
          await tempDb.rawDelete('DELETE FROM lote_items WHERE compra_id NOT IN ($listaIds)');
          await tempDb.rawDelete(
            'DELETE FROM lotes WHERE id NOT IN (SELECT DISTINCT lote_id FROM lote_items)',
          );
          await tempDb.rawDelete('DELETE FROM compras WHERE id NOT IN ($listaIds)');
        }
        // En envíos parciales al supervisor no arrastramos lotes viejos del supervisor local.
        try {
          await tempDb.delete('lotes_supervisor_items');
          await tempDb.delete('lotes_supervisor');
        } catch (_) {}
        await tempDb.execute('VACUUM');
        try {
          await tempDb.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        } catch (_) {}
        compras = ids.length;
      } finally {
        await tempDb.close();
      }
      bytesBase = await File(rutaTemp).readAsBytes();
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  final zip = Archive();
  var fotos = 0;
  final carpetaFotos = Directory(p.join(carpetaBase.path, 'fotos'));
  if (incluirFotos && await carpetaFotos.exists()) {
    for (final f in carpetaFotos.listSync().whereType<File>()) {
      final baseName = p.basename(f.path);
      if (fotosPermitidas != null && !fotosPermitidas.contains(baseName)) continue;
      zip.addFile(ArchiveFile.bytes('fotos/$baseName', await f.readAsBytes()));
      fotos++;
    }
  }
  final manifiesto = {
    'app': 'CataLog',
    'tipo': tipo,
    'version': versionRespaldo,
    'esquema': versionBaseDatos,
    'creado': (ahora ?? DateTime.now()).toIso8601String(),
    'compras': compras,
    'fotos': fotos,
    'prefijo': await _ajuste(db, 'prefijo') ?? '',
    'nombre': await _ajuste(db, 'nombre') ?? '',
    if (filtro != null && filtro.etiqueta.isNotEmpty) 'rango': filtro.etiqueta,
    if (filtro?.desde != null) 'desde': filtro!.desde!.toIso8601String(),
    if (filtro?.hastaExclusivo != null) 'hasta': filtro!.hastaExclusivo!.toIso8601String(),
  };
  zip.addFile(ArchiveFile.string(archivoManifiesto, jsonEncode(manifiesto)));
  zip.addFile(ArchiveFile.bytes(archivoBase, bytesBase));
  return ZipEncoder().encodeBytes(zip);
}

/// Abre y revisa un respaldo antes de restaurarlo.
ContenidoRespaldo leerRespaldo(List<int> bytes) {
  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes, verify: true);
  } catch (_) {
    throw RespaldoInvalido('Ese archivo no es un respaldo de CataLog (no se pudo abrir).');
  }
  final manifiesto = zip.findFile(archivoManifiesto);
  final base = zip.findFile(archivoBase);
  if (manifiesto == null || base == null) {
    throw RespaldoInvalido('Ese archivo no es un respaldo de CataLog.');
  }
  Map<String, dynamic> datos;
  try {
    datos = jsonDecode(utf8.decode(manifiesto.content)) as Map<String, dynamic>;
  } catch (_) {
    throw RespaldoInvalido('El respaldo está dañado.');
  }
  if (datos['app'] != 'CataLog') throw RespaldoInvalido('Ese archivo no es un respaldo de CataLog.');
  if (((datos['esquema'] as num?)?.toInt() ?? 1) > versionBaseDatos) {
    throw RespaldoInvalido('Ese respaldo es de una versión más nueva de CataLog. Actualiza la app primero.');
  }
  final bytesBase = base.content;
  if (bytesBase.length < 16 || ascii.decode(bytesBase.sublist(0, 15), allowInvalid: true) != 'SQLite format 3') {
    throw RespaldoInvalido('El respaldo está dañado.');
  }
  final fotos = <String, Uint8List>{
    for (final f in zip)
      if (f.isFile && f.name.startsWith('fotos/') && !f.name.contains('..') && p.basename(f.name).isNotEmpty)
        p.basename(f.name): f.content,
  };
  return ContenidoRespaldo(datos, bytesBase, fotos);
}

/// Reemplaza la base de datos y las fotos por las del respaldo.
/// La base debe estar cerrada antes de llamar a esta función.
Future<void> aplicarRespaldo(ContenidoRespaldo c, {required String rutaBase, required Directory carpetaBase}) async {
  for (final sufijo in ['-wal', '-shm', '-journal']) {
    final f = File('$rutaBase$sufijo');
    if (await f.exists()) await f.delete();
  }
  await File(rutaBase).writeAsBytes(c.base, flush: true);
  final carpetaFotos = Directory(p.join(carpetaBase.path, 'fotos'));
  if (await carpetaFotos.exists()) await carpetaFotos.delete(recursive: true);
  await carpetaFotos.create(recursive: true);
  for (final e in c.fotos.entries) {
    await File(p.join(carpetaFotos.path, e.key)).writeAsBytes(e.value, flush: true);
  }
}

/// Guarda una copia de seguridad dentro del teléfono antes de restaurar
/// (se conservan las 3 más recientes).
Future<File> guardarCopiaLocal(Uint8List zip, Directory carpetaBase, {DateTime? ahora}) async {
  final carpeta = Directory(p.join(carpetaBase.path, 'respaldos'));
  await carpeta.create(recursive: true);
  final t = (ahora ?? DateTime.now()).toIso8601String().replaceAll(RegExp('[:.]'), '-');
  final archivo = File(p.join(carpeta.path, 'antes-de-restaurar-$t.zip'));
  await archivo.writeAsBytes(zip, flush: true);
  final copias = carpeta.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final vieja in copias.skip(3)) {
    await vieja.delete();
  }
  return archivo;
}
