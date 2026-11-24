import '../data/base.dart';
import '../data/compras_repo.dart';
import '../data/dispositivo.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../i18n.dart';
import 'sistema.dart';

/// Arma y sincroniza las notificaciones locales de CataLog (con insignia grande
/// a color y prioridad Pop-up / Heads-Up):
/// - Aviso inmediato cuando se está creando o termina un respaldo.
/// - Aviso al salir de la app si quedaron stickers sin imprimir o un lote abierto.
/// - Aviso al escanear un catalítico en lotes o revisión.
/// - Recordatorios periódicos durante el día mientras haya tareas pendientes.
/// - Resumen diario de cierre de jornada a la hora elegida.
class Notificaciones {
  static const int idRespaldo = 1001;
  static const int idRecordatorio = 1002;
  static const int idPeriodico = 1003;
  static const int idAlSalir = 1004;
  static const int idEscaneo = 1005;

  static DateTime? _ultimoAvisoSalida;

  static Future<void> avisarRespaldoEnCurso(AjustesDispositivo? d, {bool automatico = false}) async {
    if (d != null && !d.notifRespaldo) return;
    await Sistema.mostrarNotificacion(
      id: idRespaldo,
      esRespaldo: true,
      enCurso: true,
      subtitulo: tr('Respaldo en curso', 'Backup in progress'),
      titulo: automatico
          ? tr('Guardando respaldo automático…', 'Saving daily auto backup…')
          : tr('Creando respaldo de CataLog…', 'Creating CataLog backup…'),
      cuerpo: tr(
        'Empaquetando tus compras y fotos en Descargas/$carpetaRespaldos.',
        'Packaging your purchases and photos in Downloads/$carpetaRespaldos.',
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
      id: idRespaldo,
      esRespaldo: true,
      enCurso: false,
      subtitulo: tr('Respaldo protegido', 'Backup protected'),
      titulo: automatico
          ? tr('✅ Copia automática guardada', '✅ Daily auto backup saved')
          : tr('✅ Respaldo guardado en el teléfono', '✅ Backup saved on phone'),
      cuerpo: tr('Actualizado en $destino', 'Updated in $destino'),
    );
  }

  /// Aviso emergente cuando se escanea un catalítico en lote o revisión.
  static Future<void> avisarCataliticoEscaneado(
    AjustesDispositivo? d, {
    required String codigo,
    required String detalle,
  }) async {
    if (d != null && !d.notifEscaneo) return;
    await Sistema.mostrarNotificacion(
      id: idEscaneo,
      subtitulo: tr('Escáner CataLog', 'CataLog Scanner'),
      titulo: tr('📦 Catalítico leído · $codigo', '📦 Converter scanned · $codigo'),
      cuerpo: detalle,
    );
  }

  /// Calcula solo las tareas urgentes pendientes (stickers sin imprimir, lote abierto,
  /// respaldo atrasado) para avisar al salir de la app y en los recordatorios periódicos.
  static Future<(String, String)?> armarPendientesUrgentes({
    required CatalogDb base,
    required AjustesDispositivo dispositivo,
    DateTime? ahora,
    bool incluirRespaldo = true,
  }) async {
    final t = ahora ?? DateTime.now();
    final compras = ComprasRepo(base, reloj: () => t);
    final lotes = LotesRepo(base, reloj: () => t);
    final lineas = <String>[];
    var sinImprimir = 0;
    var hayLoteAbierto = false;

    if (dispositivo.notifSinImprimir) {
      sinImprimir = await compras.contarSinImprimir();
      if (sinImprimir > 0) {
        lineas.add(
          sinImprimir == 1
              ? tr('• Falta sacar el sticker de 1 catalítico comprado.', '• 1 purchased converter still needs its sticker printed.')
              : tr('• Faltan sacar los stickers de $sinImprimir catalíticos.', '• $sinImprimir converters still need their stickers printed.'),
        );
      }
    }

    if (dispositivo.notifLoteAbierto) {
      final abiertos = (await lotes.listar()).where((l) => !l.lote.cerrado).toList();
      if (abiertos.isNotEmpty) {
        hayLoteAbierto = true;
        final primero = abiertos.first;
        lineas.add(
          tr(
            '• Lote abierto "${primero.lote.nombre}" (${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)}) sin cerrar.',
            '• Open batch "${primero.lote.nombre}" (${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)}) not closed yet.',
          ),
        );
      }
    }

    if (incluirRespaldo && dispositivo.notifRecordarRespaldo) {
      final aviso = await compras.avisoRespaldo();
      if (aviso != null) {
        lineas.add('• $aviso');
      }
    }

    if (lineas.isEmpty) return null;
    final String titulo;
    if (sinImprimir > 0 && hayLoteAbierto) {
      titulo = tr('⚠️ Stickers pendientes y lote abierto', '⚠️ Unprinted stickers & open batch');
    } else if (sinImprimir > 0) {
      titulo = sinImprimir == 1
          ? tr('⚠️ 1 catalítico sin sticker', '⚠️ 1 converter without sticker')
          : tr('⚠️ $sinImprimir catalíticos sin sticker', '⚠️ $sinImprimir converters without sticker');
    } else if (hayLoteAbierto) {
      titulo = tr('📦 Dejaste un lote abierto', '📦 You left a batch open');
    } else {
      titulo = tr('🔔 Respaldo pendiente · CataLog', '🔔 Pending backup · CataLog');
    }
    return (titulo, lineas.join('\n'));
  }

  /// Dispara una notificación inmediata al minimizar/salir de CataLog si hay
  /// stickers sin imprimir o un lote abierto (con pausa mínima de 45 s para no saturar).
  static Future<void> avisarAlSalirDeApp({
    required CatalogDb base,
    required AjustesDispositivo dispositivo,
    DateTime? ahora,
  }) async {
    if (!dispositivo.notifAlSalir) return;
    final t = ahora ?? DateTime.now();
    if (_ultimoAvisoSalida != null && t.difference(_ultimoAvisoSalida!) < const Duration(seconds: 45)) {
      return;
    }
    final urgente = await armarPendientesUrgentes(
      base: base,
      dispositivo: dispositivo,
      ahora: t,
      incluirRespaldo: false,
    );
    if (urgente == null) return;
    _ultimoAvisoSalida = t;
    await Sistema.mostrarNotificacion(
      id: idAlSalir,
      subtitulo: tr('Tarea pendiente en CataLog', 'Pending task in CataLog'),
      titulo: urgente.$1,
      cuerpo: urgente.$2,
    );
  }

  /// Calcula el mensaje del recordatorio del cierre de jornada según los datos
  /// actuales de compras y las preferencias activas.
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
        ? tr('🔔 Aviso de CataLog', '🔔 CataLog reminder')
        : tr('📊 Resumen del día · CataLog', '📊 Daily summary · CataLog');
    return (titulo, lineas.join('\n'));
  }

  /// Actualiza en Android tanto la alarma diaria como los recordatorios periódicos.
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
    final intervalo = dispositivo.minutosRepeticionRecordatorio;
    if (!algunActivo) {
      await Sistema.programarRecordatorio(activo: false, hora: h, minuto: m, titulo: '', cuerpo: '');
      return;
    }
    final resumen = await armarResumenRecordatorio(base: base, dispositivo: dispositivo, ahora: ahora);
    final periodico = intervalo > 0
        ? await armarPendientesUrgentes(base: base, dispositivo: dispositivo, ahora: ahora)
        : null;
    if (resumen == null && periodico == null) {
      await Sistema.programarRecordatorio(activo: false, hora: h, minuto: m, titulo: '', cuerpo: '');
      return;
    }
    await Sistema.programarRecordatorio(
      activo: true,
      hora: h,
      minuto: m,
      titulo: resumen?.$1 ?? '',
      cuerpo: resumen?.$2 ?? '',
      intervaloMinutos: periodico != null ? intervalo : 0,
      tituloPeriodico: periodico?.$1 ?? '',
      cuerpoPeriodico: periodico?.$2 ?? '',
    );
  }
}
