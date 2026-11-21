import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Fotos de los catalíticos, guardadas dentro de la carpeta de la app.
/// En la base se guarda la ruta relativa (fotos/123.jpg) para que el respaldo
/// funcione aunque cambie la carpeta del teléfono.
class FotosStore {
  FotosStore(this.carpetaBase);

  final Directory carpetaBase;

  static Future<FotosStore> abrir() async =>
      FotosStore(await getApplicationDocumentsDirectory());

  File archivo(String relativa) => File(p.join(carpetaBase.path, relativa));

  /// Copia la foto tomada con la cámara y devuelve su ruta relativa.
  Future<String> guardar(String rutaOrigen) async {
    final carpeta = Directory(p.join(carpetaBase.path, 'fotos'));
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
}
