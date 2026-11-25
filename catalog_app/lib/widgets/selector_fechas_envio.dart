import 'package:material_ui/material_ui.dart';

import '../backup/respaldo.dart';
import '../data/base.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../theme.dart';

enum OpcionRangoEnvio { hoy, sieteDias, mes, personalizado, sinLote, todas }

extension OpcionRangoEnvioExt on OpcionRangoEnvio {
  String get etiquetaChip => switch (this) {
        OpcionRangoEnvio.hoy => tr('Hoy', 'Today'),
        OpcionRangoEnvio.sieteDias => tr('Últimos 7 días', 'Last 7 days'),
        OpcionRangoEnvio.mes => tr('Este mes', 'This month'),
        OpcionRangoEnvio.personalizado => tr('Elegir fechas…', 'Pick dates…'),
        OpcionRangoEnvio.sinLote => tr('Solo sin lote', 'Unbatched only'),
        OpcionRangoEnvio.todas => tr('Todas', 'All'),
      };
}

/// Construye el [FiltroEnvioCatalog] correspondiente a [opcion] (y [rangoPersonalizado] si aplica).
FiltroEnvioCatalog construirFiltroEnvio(
  OpcionRangoEnvio opcion, {
  DateTime? ahora,
  DateTimeRange? rangoPersonalizado,
}) {
  final ref = ahora ?? DateTime.now();
  final inicioHoy = DateTime(ref.year, ref.month, ref.day);
  final manana = inicioHoy.add(const Duration(days: 1));

  return switch (opcion) {
    OpcionRangoEnvio.hoy => FiltroEnvioCatalog(
        desde: inicioHoy,
        hastaExclusivo: manana,
        etiqueta: '${tr('Hoy', 'Today')} · ${fechaCorta(inicioHoy)}',
      ),
    OpcionRangoEnvio.sieteDias => () {
        final desde = inicioHoy.subtract(const Duration(days: 6));
        return FiltroEnvioCatalog(
          desde: desde,
          hastaExclusivo: manana,
          etiqueta: '${fechaCorta(desde)} – ${fechaCorta(inicioHoy)}',
        );
      }(),
    OpcionRangoEnvio.mes => () {
        final desde = DateTime(ref.year, ref.month, 1);
        final sigMes = DateTime(ref.year, ref.month + 1, 1);
        return FiltroEnvioCatalog(
          desde: desde,
          hastaExclusivo: sigMes,
          etiqueta: '${tr('Mes', 'Month')} ${ref.month.toString().padLeft(2, '0')}/${ref.year}',
        );
      }(),
    OpcionRangoEnvio.personalizado => () {
        final r = rangoPersonalizado ?? DateTimeRange(start: inicioHoy, end: inicioHoy);
        final d = DateTime(r.start.year, r.start.month, r.start.day);
        final hFin = DateTime(r.end.year, r.end.month, r.end.day);
        final hExcl = hFin.add(const Duration(days: 1));
        final etq = d == hFin ? fechaCorta(d) : '${fechaCorta(d)} – ${fechaCorta(hFin)}';
        return FiltroEnvioCatalog(desde: d, hastaExclusivo: hExcl, etiqueta: etq);
      }(),
    OpcionRangoEnvio.sinLote => FiltroEnvioCatalog(
        soloSinLote: true,
        etiqueta: tr('Pendientes sin lote', 'Unbatched items'),
      ),
    OpcionRangoEnvio.todas => FiltroEnvioCatalog(
        etiqueta: tr('Todo el historial', 'Full history'),
      ),
  };
}

/// Elige automáticamente la mejor opción inicial por fechas para no mostrar todos los
/// catalíticos históricos cuando hay compras recientes.
Future<OpcionRangoEnvio> elegirOpcionEnvioInicial(CatalogDb base) async {
  for (final op in [OpcionRangoEnvio.hoy, OpcionRangoEnvio.sieteDias, OpcionRangoEnvio.mes]) {
    final (n, _) = await contarComprasParaEnvio(base, construirFiltroEnvio(op));
    if (n > 0) return op;
  }
  return OpcionRangoEnvio.todas;
}

class SeleccionEnvioDatos {
  const SeleccionEnvioDatos({
    required this.filtro,
    required this.conFotos,
    required this.cantidad,
    required this.montoActivo,
  });

  final FiltroEnvioCatalog filtro;
  final bool conFotos;
  final int cantidad;
  final int montoActivo;
}

/// Hoja inferior para elegir qué fechas enviar por WhatsApp / archivo (.zip) sin
/// arrastrar todo el historial de catalíticos.
Future<SeleccionEnvioDatos?> pedirOpcionesEnvioPorFechas(
  BuildContext context, {
  required CatalogDb base,
}) async {
  final inicial = await elegirOpcionEnvioInicial(base);
  final inicialFiltro = construirFiltroEnvio(inicial);
  final (cantIni, montoIni) = await contarComprasParaEnvio(base, inicialFiltro);
  if (!context.mounted) return null;

  var opcion = inicial;
  DateTimeRange? rangoCustom;
  var filtroActual = inicialFiltro;
  var cantidad = cantIni;
  var monto = montoIni;
  var conFotos = true;
  var contando = false;

  return showModalBottomSheet<SeleccionEnvioDatos>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> cambiarOpcion(OpcionRangoEnvio nueva) async {
          if (nueva == OpcionRangoEnvio.personalizado) {
            final ahora = DateTime.now();
            final elegido = await showDateRangePicker(
              context: ctx,
              firstDate: DateTime(2018),
              lastDate: ahora,
              initialDateRange: rangoCustom ??
                  DateTimeRange(
                    start: DateTime(ahora.year, ahora.month, ahora.day).subtract(const Duration(days: 6)),
                    end: DateTime(ahora.year, ahora.month, ahora.day),
                  ),
              helpText: tr('Fechas de compra a sincronizar', 'Purchase dates to sync'),
            );
            if (elegido == null) return;
            rangoCustom = elegido;
          }
          setLocal(() {
            opcion = nueva;
            filtroActual = construirFiltroEnvio(nueva, rangoPersonalizado: rangoCustom);
            contando = true;
          });
          final (n, t) = await contarComprasParaEnvio(base, filtroActual);
          if (ctx.mounted) {
            setLocal(() {
              cantidad = n;
              monto = t;
              contando = false;
            });
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Sincronizar compras por fechas', 'Sync purchases by date'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'Elige qué fechas enviar por WhatsApp o archivo para que al supervisor solo le salgan esas compras.',
                    'Choose which purchase dates to send via WhatsApp or file so the supervisor only receives that period.',
                  ),
                  style: etiqueta.copyWith(height: 1.35),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final op in OpcionRangoEnvio.values)
                      ChoiceChip(
                        label: Text(
                          op == OpcionRangoEnvio.personalizado && opcion == op
                              ? filtroActual.etiqueta
                              : op.etiquetaChip,
                        ),
                        selected: opcion == op,
                        selectedColor: CatalogColors.naranja.withValues(alpha: 0.22),
                        side: BorderSide(
                          color: opcion == op ? CatalogColors.naranja : CatalogColors.borde,
                          width: opcion == op ? 1.6 : 1,
                        ),
                        labelStyle: TextStyle(
                          fontSize: 13.5,
                          fontWeight: opcion == op ? FontWeight.w700 : FontWeight.w500,
                          color: CatalogColors.texto,
                        ),
                        onSelected: (_) => cambiarOpcion(op),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: CatalogColors.marino,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: CatalogColors.naranja,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.date_range, color: CatalogColors.marino),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filtroActual.etiqueta,
                              style: const TextStyle(
                                color: Color(0xCCFFFFFF),
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              contando
                                  ? tr('Calculando…', 'Counting…')
                                  : '${contarCataliticos(cantidad)} · ${clp(monto)}',
                              style: mono(size: 16.5, weight: FontWeight.w700, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Incluir fotos de estas fechas', 'Include photos from these dates')),
                  subtitle: Text(
                    conFotos
                        ? tr('Envía solo las fotos de las compras elegidas', 'Sends only photos for the selected purchases')
                        : tr('Solo datos y códigos (archivo mínimo)', 'Data and codes only (tiny file)'),
                    style: etiqueta,
                  ),
                  value: conFotos,
                  onChanged: (v) => setLocal(() => conFotos = v),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: (contando || cantidad == 0)
                      ? null
                      : () => Navigator.pop(
                            ctx,
                            SeleccionEnvioDatos(
                              filtro: filtroActual,
                              conFotos: conFotos,
                              cantidad: cantidad,
                              montoActivo: monto,
                            ),
                          ),
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    cantidad == 0
                        ? tr('No hay compras en esas fechas', 'No purchases on those dates')
                        : tr('Enviar por WhatsApp / Compartir', 'Send via WhatsApp / Share'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
