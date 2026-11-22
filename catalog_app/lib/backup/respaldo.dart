import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../data/base.dart';
import '../data/migraciones.dart';

// Respaldo: un .zip con la base de datos, las fotos y un manifiesto.
// Sirve para no perder las compras si se pierde o cambia el teléfono.

const archivoManifiesto = 'manifiesto.json';
const archivoBase = 'catalog.db';
const versionRespaldo = 1;

class RespaldoInvalido implements Exception {
  RespaldoInvalido(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
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
}

Future<String?> _ajuste(Database db, String clave) async {
  final filas = await db.query('ajustes', where: 'clave = ?', whereArgs: [clave]);
  return filas.isEmpty ? null : filas.first['valor'] as String?;
}

/// Arma el .zip con la base de datos y las fotos.
Future<Uint8List> armarRespaldo(CatalogDb base, Directory carpetaBase, {DateTime? ahora}) async {
  final db = base.db;
  try {
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (_) {}
  final bytesBase = await File(db.path).readAsBytes();
  final compras = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM compras')) ?? 0;

  final zip = Archive();
  var fotos = 0;
  final carpetaFotos = Directory(p.join(carpetaBase.path, 'fotos'));
  if (await carpetaFotos.exists()) {
    for (final f in carpetaFotos.listSync().whereType<File>()) {
      zip.addFile(ArchiveFile.bytes('fotos/${p.basename(f.path)}', await f.readAsBytes()));
      fotos++;
    }
  }
  final manifiesto = {
    'app': 'CataLog',
    'version': versionRespaldo,
    'esquema': versionBaseDatos,
    'creado': (ahora ?? DateTime.now()).toIso8601String(),
    'compras': compras,
    'fotos': fotos,
    'prefijo': await _ajuste(db, 'prefijo') ?? '',
    'nombre': await _ajuste(db, 'nombre') ?? '',
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
