import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../reports/excel.dart';
import '../reports/reporte.dart';
import '../theme.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';

enum _TipoReporte { hoy, semana, mes, rango, todo }

extension on _TipoReporte {
  String get etiqueta => switch (this) {
        _TipoReporte.hoy => 'Hoy',
        _TipoReporte.semana => 'Semana',
        _TipoReporte.mes => 'Mes',
        _TipoReporte.rango => 'Elegir fechas',
        _TipoReporte.todo => 'Todo',
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

  String get _titulo => _periodo?.nombre ?? 'Todas las compras';

  Future<void> _elegirRango() async {
    final ahora = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: ahora,
      initialDateRange: _rango ?? DateTimeRange(start: DateTime(ahora.year, ahora.month), end: ahora),
      helpText: 'Fechas de compra',
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
        texto: 'Reporte CataLog · $_titulo · ${clp(r.resumen.total)}',
      );
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo crear el Excel: $e');
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
          titulo: 'Elige el período',
          texto: 'Hoy, la semana, el mes, unas fechas que elijas o todas las compras. '
              'Cuenta la fecha de compra, no la del registro.',
        ),
        PasoGuia(
          clave: _gTotal,
          icono: Icons.payments_outlined,
          titulo: 'Total gastado',
          texto: 'Lo pagado en el período, cuántos catalíticos y el promedio por pieza. Las anuladas no suman.',
        ),
        PasoGuia(
          clave: _gExcel,
          icono: Icons.table_view_outlined,
          titulo: 'Exportar a Excel',
          texto: 'Arma un Excel con el resumen y una fila por compra, listo para mandar por WhatsApp o correo.',
        ),
        PasoGuia(
          clave: _gTipo,
          icono: Icons.category_outlined,
          titulo: 'Por tipo',
          texto: 'Cuánto se fue en cada tipo de catalítico. La barra muestra su parte del total.',
        ),
        PasoGuia(
          clave: _gVendedor,
          icono: Icons.people_outline,
          titulo: 'Por vendedor',
          texto: 'A quién le compraste más en el período.',
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    final periodo = _periodo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
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
                      Text(_titulo, style: etiqueta),
                      const SizedBox(height: 6),
                      Card(
                        key: _gTotal,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total gastado', style: etiqueta),
                              Text(clp(r.resumen.total), style: mono(size: 30)),
                              Text(
                                '${r.resumen.cantidad} ${r.resumen.cantidad == 1 ? 'catalítico' : 'catalíticos'}'
                                ' · promedio ${clp(r.resumen.promedio)}'
                                '${r.anuladas > 0 ? ' · ${r.anuladas} anuladas (no suman)' : ''}',
                                style: etiqueta,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: _gExcel,
                        onPressed: _exportando || compras.isEmpty ? null : () => _exportar(r),
                        icon: _exportando
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.table_view_outlined),
                        label: const Text('Exportar a Excel'),
                      ),
                      if (r.porTipo.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _Grupos(key: _gTipo, titulo: 'Por tipo', filas: r.porTipo, total: r.resumen.total),
                      ],
                      if (r.porVendedor.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _Grupos(key: _gVendedor, titulo: 'Por vendedor', filas: r.porVendedor, total: r.resumen.total),
                      ],
                      if (compras.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text('No hay compras en este período.', style: etiqueta),
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

class _Grupos extends StatelessWidget {
  const _Grupos({super.key, required this.titulo, required this.filas, required this.total});

  final String titulo;
  final List<FilaGrupo> filas;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final f in filas) ...[
              Row(
                children: [
                  Expanded(
                    child: Text('${f.nombre} · ${f.cantidad}',
                        style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                  ),
                  Text(clp(f.total), style: mono(size: 14)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : f.total / total,
                    minHeight: 6,
                    color: CatalogColors.naranja,
                    backgroundColor: CatalogColors.borde,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
