import 'package:flutter/services.dart';

/// Carpeta del teléfono donde quedan los respaldos (dentro de Descargas).
/// No se borra si se desinstala la app.
const carpetaRespaldos = 'Respaldo CataLog';

/// Un respaldo encontrado en la carpeta de respaldos.
class ArchivoRespaldo {
  const ArchivoRespaldo({required this.nombre, required this.uri, required this.fecha, required this.tamano});

  factory ArchivoRespaldo.deMapa(Map<Object?, Object?> m) => ArchivoRespaldo(
        nombre: m['nombre']! as String,
        uri: m['uri']! as String,
        fecha: DateTime.fromMillisecondsSinceEpoch((m['fecha']! as num).toInt()),
        tamano: (m['tamano']! as num).toInt(),
      );

  final String nombre;
  final String uri;
  final DateTime fecha;
  final int tamano;

  bool get esAutomatico => nombre.startsWith('CataLog-auto-');
}

/// Funciones de Android escritas en MainActivity.kt.
class Sistema {
  static const _canal = MethodChannel('cl.catalog/sistema');

  /// Archivo que se abrió con CataLog desde otra app (por ejemplo, un .zip
  /// tocado en WhatsApp). Devuelve su ruta una sola vez, o null.
  static Future<String?> archivoRecibido() async {
    try {
      return await _canal.invokeMethod<String>('archivoRecibido');
    } catch (_) {
      return null;
    }
  }

  /// Guarda un archivo en Descargas/[carpeta]. Si se indica [prefijoBorrar],
  /// deja solo los [conservar] más nuevos con ese comienzo de nombre.
  /// Devuelve dónde quedó.
  static Future<String?> guardarEnDescargas(
    String nombre,
    Uint8List bytes, {
    String carpeta = carpetaRespaldos,
    String? prefijoBorrar,
    int conservar = 3,
  }) =>
      _canal.invokeMethod<String>('guardarEnDescargas', {
        'nombre': nombre,
        'bytes': bytes,
        'carpeta': carpeta,
        'prefijoBorrar': prefijoBorrar,
        'conservar': conservar,
      });

  /// Respaldos que la app guardó en la carpeta, el más nuevo primero.
  /// (Después de reinstalar la app, Android no deja verlos: se buscan con el selector de archivos.)
  static Future<List<ArchivoRespaldo>> listarRespaldos({String carpeta = carpetaRespaldos}) async {
    final lista = await _canal.invokeListMethod<Object?>('listarRespaldos', {'carpeta': carpeta});
    return [for (final m in lista ?? const []) ArchivoRespaldo.deMapa(m! as Map<Object?, Object?>)];
  }

  static Future<Uint8List> leerArchivo(String uri) async =>
      (await _canal.invokeMethod<Uint8List>('leerArchivo', {'uri': uri}))!;

  /// Abre el explorador de archivos del teléfono directo en Descargas/[carpeta].
  static Future<bool> abrirCarpetaRespaldos({String carpeta = carpetaRespaldos}) async {
    try {
      return (await _canal.invokeMethod<bool>('abrirCarpetaRespaldos', {'carpeta': carpeta})) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pide permiso de notificaciones (Android 13+) y devuelve si están activas.
  static Future<bool> pedirPermisoNotificaciones() async {
    try {
      return (await _canal.invokeMethod<bool>('pedirPermisoNotificaciones')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Muestra una notificación local inmediata en el teléfono.
  static Future<void> mostrarNotificacion({
    required String titulo,
    required String cuerpo,
    bool esRespaldo = false,
    bool enCurso = false,
    int? id,
  }) async {
    try {
      await _canal.invokeMethod<void>('mostrarNotificacion', {
        'titulo': titulo,
        'cuerpo': cuerpo,
        'esRespaldo': esRespaldo,
        'enCurso': enCurso,
        'id': ?id,
      });
    } catch (_) {}
  }

  /// Programa o cancela el recordatorio diario a la hora elegida.
  static Future<void> programarRecordatorio({
    required bool activo,
    required int hora,
    required int minuto,
    required String titulo,
    required String cuerpo,
  }) async {
    try {
      await _canal.invokeMethod<void>('programarRecordatorio', {
        'activo': activo,
        'hora': hora,
        'minuto': minuto,
        'titulo': titulo,
        'cuerpo': cuerpo,
      });
    } catch (_) {}
  }
}
