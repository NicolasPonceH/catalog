import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../system/sistema.dart';

/// Fotos de los catalíticos, guardadas dentro de la carpeta de la app.
/// En la base se guarda la ruta relativa (fotos/123.jpg) para que el respaldo
/// funcione aunque cambie la carpeta del teléfono.
class FotosStore {
  FotosStore(this.carpetaBase);

  final Directory carpetaBase;

  Directory get carpetaFotos => Directory(p.join(carpetaBase.path, 'fotos'));

  static Future<FotosStore> abrir() async =>
      FotosStore(await getApplicationDocumentsDirectory());

  File archivo(String relativa) => File(p.join(carpetaBase.path, relativa));

  /// Copia la foto tomada con la cámara y devuelve su ruta relativa.
  Future<String> guardar(String rutaOrigen) async {
    final carpeta = carpetaFotos;
    await carpeta.create(recursive: true);
    final relativa = 'fotos/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(rutaOrigen).copy(p.join(carpetaBase.path, relativa));
    return relativa;
  }

  Future<void> borrar(String? relativa) async {
    if (relativa == null) return;
    final f = archivo(relativa);
    if (await f.exists()) await f.delete();
  }

  /// Cantidad de fotos almacenadas y cuánto pesan en total (en bytes).
  Future<(int cantidad, int bytes)> estadisticas() async {
    final dir = carpetaFotos;
    if (!await dir.exists()) return (0, 0);
    var n = 0;
    var total = 0;
    for (final f in dir.listSync().whereType<File>()) {
      try {
        total += await f.length();
        n++;
      } catch (_) {}
    }
    return (n, total);
  }

  /// Recomprime las fotos antiguas que pesen de más para liberar espacio en el celular.
  Future<(int optimizadas, int bytesAhorrados)> optimizarGuardadas({
    int maxLado = 1024,
    int calidad = 62,
  }) async {
    final dir = carpetaFotos;
    if (!await dir.exists()) return (0, 0);
    return Sistema.optimizarFotos(dir.path, maxLado: maxLado, calidad: calidad);
  }
}
