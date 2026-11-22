import 'package:flutter/services.dart';

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

  /// Guarda un archivo en Descargas/CataLog (no se borra al desinstalar la app).
  /// Si se indica [prefijoBorrar], deja solo los [conservar] más nuevos con ese
  /// comienzo de nombre. Devuelve dónde quedó.
  static Future<String?> guardarEnDescargas(
    String nombre,
    Uint8List bytes, {
    String? prefijoBorrar,
    int conservar = 3,
  }) =>
      _canal.invokeMethod<String>('guardarEnDescargas', {
        'nombre': nombre,
        'bytes': bytes,
        'prefijoBorrar': prefijoBorrar,
        'conservar': conservar,
      });
}
