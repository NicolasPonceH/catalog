import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../backup/respaldo.dart';

/// Sesión de compra: las compras propias de este teléfono.
/// Sesión de revisión: datos recibidos de otro celular, solo para ver y escanear.
enum TipoSesion { compra, revision }

class Sesion {
  const Sesion({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.rutaBase,
    required this.carpeta,
    this.origen = '',
    this.prefijo = '',
    this.recibidaEn,
    this.datosDel,
    this.compras = 0,
  });

  final String id;
  final TipoSesion tipo;
  final String nombre;

  /// Archivo de la base de datos de esta sesión.
  final String rutaBase;

  /// Carpeta donde están sus fotos (carpeta/fotos/...).
  final Directory carpeta;

  /// Quién mandó los datos (nombre configurado en su teléfono).
  final String origen;
  final String prefijo;
  final DateTime? recibidaEn;

  /// Fecha en que el otro teléfono armó el archivo.
  final DateTime? datosDel;
  final int compras;

  bool get esRevision => tipo == TipoSesion.revision;
}

const idSesionPrincipal = 'principal';

/// Todas las sesiones guardadas en el teléfono.
class Sesiones {
  Sesiones(this.documentos, this.rutaPrincipal);

  final Directory documentos;
  final String rutaPrincipal;

  static Future<Sesiones> abrir() async => Sesiones(
        await getApplicationDocumentsDirectory(),
        p.join(await getDatabasesPath(), archivoBase),
      );

  Sesion get principal => Sesion(
        id: idSesionPrincipal,
        tipo: TipoSesion.compra,
        nombre: 'Mis compras',
        rutaBase: rutaPrincipal,
        carpeta: documentos,
      );

  Directory get _carpetaRevisiones => Directory(p.join(documentos.path, 'sesiones'));

  Future<List<Sesion>> revisiones() async {
    final carpeta = _carpetaRevisiones;
    if (!await carpeta.exists()) return [];
    final lista = <Sesion>[];
    for (final dir in carpeta.listSync().whereType<Directory>()) {
      final info = File(p.join(dir.path, 'info.json'));
      if (!await info.exists()) continue;
      try {
        final j = jsonDecode(await info.readAsString()) as Map<String, dynamic>;
        lista.add(Sesion(
          id: p.basename(dir.path),
          tipo: TipoSesion.revision,
          nombre: j['nombre'] as String? ?? 'Revisión',
          rutaBase: p.join(dir.path, archivoBase),
          carpeta: dir,
          origen: j['origen'] as String? ?? '',
          prefijo: j['prefijo'] as String? ?? '',
          recibidaEn: DateTime.tryParse(j['recibidaEn'] as String? ?? ''),
          datosDel: DateTime.tryParse(j['datosDel'] as String? ?? ''),
          compras: (j['compras'] as num?)?.toInt() ?? 0,
        ));
      } catch (_) {}
    }
    lista.sort((a, b) => (b.recibidaEn ?? DateTime(2000)).compareTo(a.recibidaEn ?? DateTime(2000)));
    return lista;
  }

  Future<Sesion?> buscar(String? id) async {
    if (id == null || id == idSesionPrincipal) return principal;
    for (final s in await revisiones()) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Guarda los datos recibidos como sesión de revisión. Si ya había una
  /// revisión del mismo teléfono (mismo prefijo), se actualiza esa.
  /// La base de esa sesión no debe estar abierta.
  Future<Sesion> guardarRevision(ContenidoRespaldo c, {DateTime? ahora}) async {
    final cuando = ahora ?? DateTime.now();
    Sesion? anterior;
    if (c.prefijo.isNotEmpty) {
      for (final s in await revisiones()) {
        if (s.prefijo == c.prefijo) anterior = s;
      }
    }
    final id = anterior?.id ?? 'r${cuando.millisecondsSinceEpoch}';
    final carpeta = Directory(p.join(_carpetaRevisiones.path, id));
    await carpeta.create(recursive: true);
    await aplicarRespaldo(c, rutaBase: p.join(carpeta.path, archivoBase), carpetaBase: carpeta);

    final quien = c.nombre.isNotEmpty ? c.nombre : c.prefijo;
    final nombre = quien.isEmpty ? 'Revisión' : 'Revisión de $quien';
    await File(p.join(carpeta.path, 'info.json')).writeAsString(jsonEncode({
      'nombre': nombre,
      'origen': c.nombre,
      'prefijo': c.prefijo,
      'recibidaEn': cuando.toIso8601String(),
      'datosDel': c.creado?.toIso8601String(),
      'compras': c.compras,
    }), flush: true);
    return (await buscar(id))!;
  }

  /// Borra una sesión de revisión (sus datos son una copia; los originales
  /// siguen en el otro teléfono). La sesión de compra nunca se borra.
  Future<void> eliminar(Sesion s) async {
    if (!s.esRevision) return;
    if (await s.carpeta.exists()) await s.carpeta.delete(recursive: true);
  }
}
