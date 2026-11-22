import 'package:local_auth/local_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/catalog_logo.dart';

/// Bloqueo con huella, rostro o el PIN/patrón del teléfono.
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

/// Se muestra encima de todo mientras la app está bloqueada.
class PantallaBloqueo extends StatefulWidget {
  const PantallaBloqueo({super.key, required this.alDesbloquear});

  final VoidCallback alDesbloquear;

  @override
  State<PantallaBloqueo> createState() => _PantallaBloqueoState();
}

class _PantallaBloqueoState extends State<PantallaBloqueo> {
  bool _pidiendo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedir());
  }

  Future<void> _pedir() async {
    if (_pidiendo) return;
    setState(() => _pidiendo = true);
    final ok = await Bloqueo.desbloquear();
    if (!mounted) return;
    setState(() => _pidiendo = false);
    if (ok) widget.alDesbloquear();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CatalogColors.marino,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CatalogLogo(altura: 40, oscuro: true),
                const SizedBox(height: 40),
                const Icon(Icons.lock_outline, color: CatalogColors.niebla, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'CataLog está bloqueado',
                  style: TextStyle(color: CatalogColors.niebla, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _pidiendo ? null : _pedir,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Desbloquear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
