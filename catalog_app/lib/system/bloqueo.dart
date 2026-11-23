import 'package:local_auth/local_auth.dart';

/// Bloqueo con huella, rostro o el PIN/patrón del teléfono.
/// La pantalla que lo pide al abrir la app es la Bienvenida (features/bienvenida.dart).
class Bloqueo {
  static final _auth = LocalAuthentication();

  /// True si el teléfono tiene configurado algún bloqueo de pantalla.
  static Future<bool> disponible() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> desbloquear([String motivo = 'Desbloquea CataLog']) async {
    try {
      return await _auth.authenticate(
        localizedReason: motivo,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
