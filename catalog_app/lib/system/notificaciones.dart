import '../data/base.dart';
import '../data/compras_repo.dart';
import '../data/dispositivo.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../i18n.dart';
import 'sistema.dart';

/// Arma y sincroniza las notificaciones locales de CataLog (100 % sin internet):
/// - Aviso inmediato cuando se está creando o termina un respaldo.
/// - Recordatorio diario a la hora elegida (stickers pendientes, resumen del día,
///   lote abierto y respaldo externo).
class Notificaciones {
  static Future<void> avisarRespaldoEnCurso(AjustesDispositivo? d, {bool automatico = false}) async {
    if (d != null && !d.notifRespaldo) return;
    await Sistema.mostrarNotificacion(
      esRespaldo: true,
      enCurso: true,
      titulo: automatico
          ? tr('Guardando respaldo automático…', 'Saving daily auto backup…')
          : tr('Creando respaldo de CataLog…', 'Creating CataLog backup…'),
      cuerpo: tr(
        'Guardando tus compras y fotos en Descargas/$carpetaRespaldos.',
        'Saving your purchases and photos in Downloads/$carpetaRespaldos.',
      ),
    );
  }

  static Future<void> avisarRespaldoListo(
    AjustesDispositivo? d, {
    required String? lugar,
    bool automatico = false,
  }) async {
    if (d != null && !d.notifRespaldo) return;
    final destino = lugar ?? 'Descargas/$carpetaRespaldos';
    await Sistema.mostrarNotificacion(
      esRespaldo: true,
      enCurso: false,
      titulo: automatico
          ? tr('Copia automática guardada', 'Daily auto backup saved')
          : tr('Respaldo guardado en el teléfono', 'Backup saved on phone'),
      cuerpo: tr('Quedó seguro en $destino', 'Safely stored in $destino'),
    );
  }

  /// Calcula el mensaje del recordatorio del cierre de jornada según los datos
  /// actuales de la sesión de compra y las preferencias activas.
  static Future<(String, String)?> armarResumenRecordatorio({
    required CatalogDb base,
    required AjustesDispositivo dispositivo,
    DateTime? ahora,
  }) async {
    final t = ahora ?? DateTime.now();
    final compras = ComprasRepo(base, reloj: () => t);
    final lotes = LotesRepo(base, reloj: () => t);
    final lineas = <String>[];

    if (dispositivo.notifSinImprimir) {
      final sinImprimir = await compras.contarSinImprimir();
      if (sinImprimir > 0) {
        lineas.add(
          sinImprimir == 1
              ? tr('• 1 catalítico tiene su sticker pendiente de imprimir.', '• 1 converter is waiting for its sticker.')
              : tr('• $sinImprimir catalíticos tienen su sticker sin imprimir.', '• $sinImprimir converters have unprinted stickers.'),
        );
      }
    }

    if (dispositivo.notifLoteAbierto) {
      final abiertos = (await lotes.listar()).where((l) => !l.lote.cerrado).toList();
      if (abiertos.isNotEmpty) {
        final primero = abiertos.first;
        lineas.add(
          tr(
            '• Lote abierto "${primero.lote.nombre}" (${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)}).',
            '• Open batch "${primero.lote.nombre}" (${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)}).',
          ),
        );
      }
    }

    if (dispositivo.notifResumenDia) {
      final hoy = await compras.resumen(periodoHoy(t));
      if (hoy.cantidad > 0) {
        lineas.add(
          tr(
            '• Hoy registraste ${contarCataliticos(hoy.cantidad)} por ${clp(hoy.total)}.',
            '• Today you logged ${contarCataliticos(hoy.cantidad)} for ${clp(hoy.total)}.',
          ),
        );
      }
    }

    if (dispositivo.notifRecordarRespaldo) {
      final aviso = await compras.avisoRespaldo();
      if (aviso != null) {
        lineas.add('• $aviso');
      }
    }

    if (lineas.isEmpty) return null;
    final titulo = lineas.length == 1
        ? tr('Aviso de CataLog', 'CataLog reminder')
        : tr('Resumen del día · CataLog', 'Daily summary · CataLog');
    return (titulo, lineas.join('\n'));
  }

  /// Actualiza la alarma diaria en Android con los datos actuales.
  static Future<void> sincronizarRecordatorioDiario({
    required CatalogDb base,
    required AjustesDispositivo dispositivo,
    DateTime? ahora,
  }) async {
    final algunActivo = dispositivo.notifSinImprimir ||
        dispositivo.notifLoteAbierto ||
        dispositivo.notifResumenDia ||
        dispositivo.notifRecordarRespaldo;
    final (h, m) = dispositivo.horaMinutoRecordatorio;
    if (!algunActivo) {
      await Sistema.programarRecordatorio(activo: false, hora: h, minuto: m, titulo: '', cuerpo: '');
      return;
    }
    final resumen = await armarResumenRecordatorio(base: base, dispositivo: dispositivo, ahora: ahora);
    if (resumen == null) {
      await Sistema.programarRecordatorio(activo: false, hora: h, minuto: m, titulo: '', cuerpo: '');
      return;
    }
    await Sistema.programarRecordatorio(
      activo: true,
      hora: h,
      minuto: m,
      titulo: resumen.$1,
      cuerpo: resumen.$2,
    );
  }
}
