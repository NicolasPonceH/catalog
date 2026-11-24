import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'compras_repo.dart';

/// Ajustes de ESTE TELÉFONO, que no dependen de la sesión abierta:
/// impresora, papel, bloqueo, respaldo automático y sesión activa.
class AjustesDispositivo extends ChangeNotifier {
  AjustesDispositivo._(this._archivo, this._datos);

  // ---- Apariencia y preferencias (avisan a la app cuando cambian) ----

  /// 'claro', 'oscuro' o 'auto' (sigue al teléfono).
  static const tema = 'tema';

  /// '1' = alto contraste.
  static const contraste = 'contraste';

  /// Tamaño de letra: '1.0', '1.15' o '1.3' (sobre el del teléfono).
  static const letra = 'letra';

  /// '1' = sin animaciones.
  static const sinAnimaciones = 'sin_animaciones';

  /// '1' = no vibrar / no sonar al escanear.
  static const sinVibrar = 'sin_vibrar';
  static const sinSonido = 'sin_sonido';

  /// 'es' (español) o 'en' (inglés).
  static const idioma = 'idioma';

  String get temaElegido => leer(tema) ?? 'claro';
  String get idiomaElegido => leer(idioma) == 'en' ? 'en' : 'es';
  double get escalaLetra => double.tryParse(leer(letra) ?? '') ?? 1.0;
  bool get vibrar => !activado(sinVibrar);
  bool get sonar => !activado(sinSonido);

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
    notifyListeners();
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
