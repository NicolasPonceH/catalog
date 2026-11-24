import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../i18n.dart';
import 'bloqueo.dart';

/// Antes de borrar o anular algo, pide la huella, el rostro o el PIN del teléfono.
/// Si el teléfono no tiene bloqueo de pantalla configurado, basta la
/// confirmación en pantalla que ya se mostró.
Future<bool> confirmarConHuella(BuildContext context, String motivo) async {
  if (!await Bloqueo.disponible()) return true;
  final ok = await Bloqueo.desbloquear(motivo);
  if (!ok && context.mounted) {
    avisar(
      context,
      tr('No se confirmó con huella o PIN: no se borró nada', 'Fingerprint or PIN not confirmed: nothing was deleted'),
    );
  }
  return ok;
}
