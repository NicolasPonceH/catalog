import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'compras_repo.dart';

/// Ajustes de ESTE TELÉFONO, que no dependen de la sesión abierta:
/// impresora, papel, bloqueo, respaldo automático y sesión activa.
class AjustesDispositivo {
  AjustesDispositivo._(this._archivo, this._datos);

  final File _archivo;
  final Map<String, dynamic> _datos;

  static const impresora = 'impresora';
  static const anchoPapel = 'ancho_papel';
  static const bloqueo = 'bloqueo';
  static const sesionActiva = 'sesion_activa';
  static const ultimoAutoRespaldo = 'auto_respaldo';
  static const lugarAutoRespaldo = 'auto_respaldo_lugar';

  /// Ya se vio la presentación (carrusel) de la primera vez.
  static const presentacionVista = 'presentacion_vista';

  /// Ya se usó el botón de ayuda (deja de destacarse).
  static const ayudaUsada = 'ayuda_usada';

  static Future<AjustesDispositivo> abrir(Directory carpeta) async {
    final archivo = File(p.join(carpeta.path, 'dispositivo.json'));
    var datos = <String, dynamic>{};
    if (await archivo.exists()) {
      try {
        datos = jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    return AjustesDispositivo._(archivo, datos);
  }

  String? leer(String clave) => _datos[clave] as String?;

  bool activado(String clave) => _datos[clave] == '1';

  DateTime? fecha(String clave) => DateTime.tryParse(leer(clave) ?? '');

  Future<void> guardar(String clave, String? valor) async {
    if (valor == null) {
      _datos.remove(clave);
    } else {
      _datos[clave] = valor;
    }
    await _archivo.parent.create(recursive: true);
    await _archivo.writeAsString(jsonEncode(_datos), flush: true);
  }

  /// En la versión 1.0 la impresora se guardaba en la base de compras.
  /// Se pasa una sola vez a los ajustes del teléfono.
  Future<void> migrarDesde(ComprasRepo repo) async {
    for (final clave in [impresora, anchoPapel]) {
      if (leer(clave) != null) continue;
      final valor = await repo.leerAjuste(clave);
      if (valor != null) await guardar(clave, valor);
    }
  }
}
