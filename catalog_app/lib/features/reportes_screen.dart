import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import '../reports/excel.dart';
import '../reports/reporte.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'bienvenida.dart';

enum _TipoReporte { hoy, semana, mes, rango, todo }

extension on _TipoReporte {
  String get etiqueta => switch (this) {
        _TipoReporte.hoy => tr('Hoy', 'Today'),
        _TipoReporte.semana => tr('Semana', 'Week'),
        _TipoReporte.mes => tr('Mes', 'Month'),
        _TipoReporte.rango => tr('Elegir fechas', 'Custom dates'),
        _TipoReporte.todo => tr('Todo', 'All'),
      };
}

/// Lo gastado por período, por tipo y por vendedor, con exportación a Excel.
class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  _TipoReporte _tipo = _TipoReporte.mes;
  DateTimeRange? _rango;
  bool _exportando = false;

  Periodo? get _periodo {
    final ahora = DateTime.now();
    return switch (_tipo) {
      _TipoReporte.hoy => periodoHoy(ahora),
      _TipoReporte.semana => periodoSemana(ahora),
      _TipoReporte.mes => periodoMes(ahora),
      _TipoReporte.rango => _rango == null ? periodoMes(ahora) : periodoRango(_rango!.start, _rango!.end),
      _TipoReporte.todo => null,
    };
  }

  String get _titulo => _periodo?.nombre ?? tr('Todas las compras', 'All purchases');

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: ahora,
      initialDateRange: _rango ?? DateTimeRange(start: DateTime(ahora.year, ahora.month), end: ahora),
      helpText: tr('Fechas de compra', 'Purchase dates'),
    );
    if (r != null) {
      setState(() {
        _rango = r;
        _tipo = _TipoReporte.rango;
      });
    }
  }

  Future<void> _exportar(Reporte r) async {
    setState(() => _exportando = true);
    try {
      final comprador = await AppScope.of(context).compras.leerAjuste('nombre') ?? '';
      final bytes = excelDeReporte(r, comprador: comprador);
      final hoy = DateTime.now();
      await compartirExcel(
        bytes,
        'CataLog ${_titulo.replaceAll('/', '-')} (${fechaCorta(hoy).replaceAll('/', '-')}).xlsx',
        texto: '${tr('Reporte CataLog', 'CataLog Report')} · $_titulo · ${clp(r.resumen.total)}',
      );
    } catch (e) {
      if (mounted) avisar(context, '${tr('No se pudo crear el Excel', 'Could not create Excel')}: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // Partes que ilumina la guía.
  final _gPeriodo = GlobalKey();
  final _gTotal = GlobalKey();
  final _gExcel = GlobalKey();
  final _gTipo = GlobalKey();
  final _gVendedor = GlobalKey();

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gPeriodo,
          icono: Icons.date_range,
          titulo: tr('Elige el período', 'Choose period'),
          texto: tr(
            'Hoy, la semana, el mes, unas fechas que elijas o todas las compras. Cuenta la fecha de compra, no la del registro.',
            'Today, this week, this month, a custom date range, or all purchases. Uses the purchase date, not when it was logged.',
          ),
        ),
        PasoGuia(
          clave: _gTotal,
          icono: Icons.payments_outlined,
          titulo: tr('Total gastado', 'Total spent'),
          texto: tr(
            'Lo pagado en el período, cuántos catalíticos y el promedio por pieza. Las anuladas no suman.',
            'Total paid in the period, converter count, and average per unit. Voided items are excluded.',
          ),
        ),
        PasoGuia(
          clave: _gExcel,
          icono: Icons.table_view_outlined,
          titulo: tr('Exportar a Excel', 'Export to Excel'),
          texto: tr(
            'Arma un Excel con el resumen y una fila por compra, listo para mandar por WhatsApp o correo.',
            'Builds a multi-sheet Excel with summary and one row per purchase, ready to share via WhatsApp or email.',
          ),
        ),
        PasoGuia(
          clave: _gTipo,
          icono: Icons.category_outlined,
          titulo: tr('Por tipo', 'By type'),
          texto: tr(
            'Cuánto se fue en cada tipo de catalítico, con su color y porcentaje del total.',
            'How much went into each converter type, with its color badge and share of the total.',
          ),
        ),
        PasoGuia(
          clave: _gVendedor,
          icono: Icons.people_outline,
          titulo: tr('Por vendedor', 'By seller'),
          texto: tr(
            'A quién le compraste más en el período.',
            'Who you bought the most from during the period.',
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final repo = scope.compras;
    final revision = scope.soloLectura;
    final periodo = _periodo;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Reportes', 'Reports')),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              key: _gPeriodo,
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                children: [
                  for (final t in _TipoReporte.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t.etiqueta),
                        selected: _tipo == t,
                        showCheckmark: false,
                        selectedColor: CatalogColors.paleta.oscura ? CatalogColors.naranja : CatalogColors.marino,
                        labelStyle: TextStyle(
                          color: _tipo == t
                              ? (CatalogColors.paleta.oscura ? CatalogColors.marino : CatalogColors.niebla)
                              : CatalogColors.texto,
                          fontWeight: _tipo == t ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (_) =>
                            t == _TipoReporte.rango ? _elegirRango() : setState(() => _tipo = t),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Consulta<List<Compra>>(
                claves: [periodo?.desde, periodo?.hasta, _tipo],
                cargar: () => repo.comprasDelPeriodo(periodo),
                builder: (context, compras) {
                  if (compras == null) return const Center(child: CircularProgressIndicator());
                  final r = Reporte.de(compras, titulo: _titulo);
                  return ListView(
                    scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye todo el reporte, para la guía
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      _TarjetaResumenReporte(
                        key: _gTotal,
                        tituloPeriodo: _titulo,
                        reporte: r,
                        revision: revision,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: _gExcel,
                        onPressed: _exportando || compras.isEmpty ? null : () => _exportar(r),
                        icon: _exportando
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.table_view_outlined),
                        label: Text(tr('Exportar a Excel', 'Export to Excel')),
                      ),
                      if (r.porTipo.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _Grupos(
                          key: _gTipo,
                          titulo: tr('Por tipo', 'By type'),
                          icono: Icons.category_outlined,
                          colorIcono: const Color(0xFF7F77DD),
                          filas: r.porTipo,
                          total: r.resumen.total,
                          esTipo: true,
                        ),
                      ],
                      if (r.porVendedor.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _Grupos(
                          key: _gVendedor,
                          titulo: tr('Por vendedor', 'By seller'),
                          icono: Icons.people_outline,
                          colorIcono: const Color(0xFF1D9E75),
                          filas: r.porVendedor,
                          total: r.resumen.total,
                          esTipo: false,
                        ),
                      ],
                      if (compras.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: CatalogColors.naranjaClara,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.bar_chart_outlined, color: CatalogColors.naranja),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      tr('No hay compras en este período.', 'No purchases in this period.'),
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta principal azul marino del reporte, hermanada con la del Inicio.
class _TarjetaResumenReporte extends StatelessWidget {
  const _TarjetaResumenReporte({
    super.key,
    required this.tituloPeriodo,
    required this.reporte,
    required this.revision,
  });

  final String tituloPeriodo;
  final Reporte reporte;
  final bool revision;

  @override
  Widget build(BuildContext context) {
    const tenue = Color(0xB3FFFFFF);
    final r = reporte.resumen;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CatalogColors.marino,
        borderRadius: BorderRadius.circular(18),
        border: CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1
            ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${revision ? tr('Total recibido', 'Total received') : tr('Total gastado', 'Total spent')} · $tituloPeriodo',
                  style: const TextStyle(color: tenue, fontSize: 13),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(clp(r.total), style: mono(size: 30, color: CatalogColors.naranja)),
                ),
                Text(
                  '${contarCataliticos(r.cantidad)}'
                  '${r.cantidad > 0 ? ' · ${tr('promedio', 'avg')} ${clp(r.promedio)}' : ''}',
                  style: const TextStyle(color: tenue, fontSize: 12.5),
                ),
                if (reporte.anuladas > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x33FF8A80),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      tr(
                        '${reporte.anuladas} ${reporte.anuladas == 1 ? 'anulada' : 'anuladas'} (no suman)',
                        '${reporte.anuladas} voided (excluded)',
                      ),
                      style: const TextStyle(color: Color(0xFFFFB4A8), fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CatalogColors.naranja.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.insights_outlined, color: CatalogColors.naranja, size: 24),
          ),
        ],
      ),
    );
  }
}

TipoMaterial? _materialDeNombre(String nombre) {
  final n = nombre.toLowerCase();
  if (n.startsWith('dpf')) return TipoMaterial.dpf;
  if (n.startsWith('met')) return TipoMaterial.metalico;
  if (n.startsWith('cer')) return TipoMaterial.ceramico;
  return null;
}

class _Grupos extends StatelessWidget {
  const _Grupos({
    super.key,
    required this.titulo,
    required this.icono,
    required this.colorIcono,
    required this.filas,
    required this.total,
    required this.esTipo,
  });

  final String titulo;
  final IconData icono;
  final Color colorIcono;
  final List<FilaGrupo> filas;
  final int total;
  final bool esTipo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: colorIcono, borderRadius: BorderRadius.circular(9)),
                  child: Icon(icono, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var idx = 0; idx < filas.length; idx++) ...[
              Builder(builder: (context) {
                final f = filas[idx];
                final fraccion = total == 0 ? 0.0 : (f.total / total).clamp(0.0, 1.0);
                final pct = (fraccion * 100).round();
                final mat = esTipo ? _materialDeNombre(f.nombre) : null;
                final colorBarra = mat != null ? MarcaTipo.colorDe(mat) : CatalogColors.naranja;
                final ini = iniciales(f.nombre);
                return Padding(
                  padding: EdgeInsets.only(bottom: idx == filas.length - 1 ? 0 : 12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (mat != null) ...[
                            MarcaTipo(material: mat, tamano: 28),
                            const SizedBox(width: 10),
                          ] else ...[
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: CatalogColors.naranjaClara,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ini.isEmpty ? '#' : ini,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: CatalogColors.paleta.oscura ? CatalogColors.naranja : CatalogColors.marino,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.nombre,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text('${contarCataliticos(f.cantidad)} · $pct%', style: etiqueta.copyWith(fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(clp(f.total), style: mono(size: 14.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: fraccion,
                          minHeight: 6,
                          color: colorBarra,
                          backgroundColor: CatalogColors.borde,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
