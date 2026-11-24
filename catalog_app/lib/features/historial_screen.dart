import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';

/// Al subir su valor, Historial activa automáticamente el filtro "Sin imprimir".
final pedirFiltroSinImprimir = ValueNotifier<int>(0);

/// Todas las compras, agrupadas por día de compra, con búsqueda y filtros.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _buscar = TextEditingController();
  TipoPeriodo _periodo = TipoPeriodo.todo;
  TipoMaterial? _material;
  bool _sinImprimir = false;

  // Partes que ilumina la guía.
  final _gBuscar = GlobalKey();
  final _gFiltros = GlobalKey();
  final _gResumen = GlobalKey();
  final _gPrimera = GlobalKey();

  @override
  void initState() {
    super.initState();
    pedirFiltroSinImprimir.addListener(_activarSinImprimir);
  }

  void _activarSinImprimir() {
    if (!mounted) return;
    setState(() {
      _sinImprimir = true;
      _periodo = TipoPeriodo.todo;
    });
  }

  @override
  void dispose() {
    pedirFiltroSinImprimir.removeListener(_activarSinImprimir);
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _mostrarGuia() {
    FocusManager.instance.primaryFocus?.unfocus();
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gBuscar,
        icono: Icons.search,
        titulo: tr('Buscar', 'Search'),
        texto: tr(
          'Escribe parte del vendedor, el código, el auto, el lugar o el código de fábrica.',
          'Type part of the seller, code, vehicle, place, or factory code.',
        ),
      ),
      PasoGuia(
        clave: _gFiltros,
        icono: Icons.filter_list,
        titulo: tr('Filtros', 'Filters'),
        texto: tr(
          'Elige el período, filtra los stickers "Sin imprimir" para sacarlos seguidos en bodega o filtra por material.',
          'Filter by period, tap "Unprinted" to print pending stickers in one pass, or filter by material.',
        ),
      ),
      PasoGuia(
        clave: _gResumen,
        icono: Icons.functions,
        titulo: tr('Total del filtro', 'Filtered total'),
        texto: tr(
          'Cuántos catalíticos, cuánto pagaste y el promedio de los que muestra la lista. Las anuladas no suman.',
          'Converter count, total paid, and average price for the filtered list. Voided items are excluded.',
        ),
      ),
      PasoGuia(
        clave: _gPrimera,
        icono: Icons.touch_app_outlined,
        titulo: tr('Abrir una compra', 'Open a purchase'),
        texto: tr(
          'Las compras van por día de compra, de la más nueva a la más vieja. Toca una para ver su ficha.',
          'Purchases are grouped by purchase day, newest first. Tap any row to inspect its full record.',
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Historial de compras', 'Purchase history')),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              key: _gBuscar,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                controller: _buscar,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr('Buscar vendedor, código, auto o lugar', 'Search seller, code, vehicle, or place'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _buscar.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(_buscar.clear),
                        ),
                ),
              ),
            ),
            SizedBox(
              key: _gFiltros,
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final t in TipoPeriodo.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t.etiqueta),
                        selected: _periodo == t,
                        showCheckmark: false,
                        selectedColor: CatalogColors.paleta.oscura ? CatalogColors.naranja : CatalogColors.marino,
                        labelStyle: TextStyle(
                          color: _periodo == t
                              ? (CatalogColors.paleta.oscura ? CatalogColors.marino : CatalogColors.niebla)
                              : CatalogColors.texto,
                          fontWeight: _periodo == t ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (_) => setState(() => _periodo = t),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Consulta<int>(
                    cargar: repo.contarSinImprimir,
                    builder: (context, pendientes) {
                      final n = pendientes ?? 0;
                      final etiquetaChip = n > 0
                          ? '${tr('Sin imprimir', 'Unprinted')} ($n)'
                          : tr('Sin imprimir', 'Unprinted');
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(
                            Icons.print_disabled_outlined,
                            size: 16,
                            color: _sinImprimir ? CatalogColors.marino : CatalogColors.naranja,
                          ),
                          label: Text(etiquetaChip),
                          selected: _sinImprimir,
                          showCheckmark: false,
                          selectedColor: CatalogColors.naranja,
                          labelStyle: TextStyle(
                            color: _sinImprimir ? CatalogColors.marino : CatalogColors.texto,
                            fontWeight: _sinImprimir ? FontWeight.w700 : FontWeight.w500,
                          ),
                          onSelected: (s) => setState(() => _sinImprimir = s),
                        ),
                      );
                    },
                  ),
                  for (final m in TipoMaterial.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        avatar: CircleAvatar(
                          radius: 6,
                          backgroundColor: _material == m ? Colors.white : MarcaTipo.colorDe(m),
                        ),
                        label: Text(m.etiqueta),
                        selected: _material == m,
                        showCheckmark: false,
                        selectedColor: MarcaTipo.colorDe(m),
                        labelStyle: TextStyle(
                          color: _material == m ? Colors.white : CatalogColors.texto,
                          fontWeight: _material == m ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (s) => setState(() => _material = s ? m : null),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Consulta<List<Compra>>(
                claves: [_buscar.text, _periodo, _material, _sinImprimir],
                cargar: () => repo.historial(FiltroHistorial(
                  texto: _buscar.text,
                  periodo: periodoDe(_periodo, DateTime.now()),
                  material: _material,
                  soloSinImprimir: _sinImprimir,
                )),
                builder: (context, lista) {
                  if (lista == null) return const Center(child: CircularProgressIndicator());
                  return _Lista(compras: lista, claveResumen: _gResumen, clavePrimera: _gPrimera);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Lista extends StatelessWidget {
  const _Lista({required this.compras, this.claveResumen, this.clavePrimera});

  final List<Compra> compras;
  final Key? claveResumen;
  final Key? clavePrimera;

  @override
  Widget build(BuildContext context) {
    final activas = compras.where((c) => !c.anulada).toList();
    final total = activas.fold<int>(0, (s, c) => s + c.precio);
    final promedio = activas.isEmpty ? 0 : (total / activas.length).round();
    final hoy = DateTime.now();

    // Encabezado por día de compra, seguido de las compras de ese día.
    final items = <Object>[];
    DateTime? diaAnterior;
    for (final c in compras) {
      final dia = DateTime(c.fechaCompra.year, c.fechaCompra.month, c.fechaCompra.day);
      if (dia != diaAnterior) {
        items.add(dia);
        diaAnterior = dia;
      }
      items.add(c);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          if (compras.isEmpty) {
            return Padding(
              key: claveResumen,
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: CatalogColors.naranjaClara,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.search_off, color: CatalogColors.naranja),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          tr('No hay compras con estos filtros.', 'No purchases match these filters.'),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return Padding(
            key: claveResumen,
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: CatalogColors.marino,
                borderRadius: BorderRadius.circular(14),
                border: CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1
                    ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${contarCataliticos(activas.length)}'
                      '${activas.isNotEmpty ? ' · ${tr('prom.', 'avg')} ${clp(promedio)}' : ''}',
                      style: const TextStyle(color: CatalogColors.niebla, fontSize: 13.5, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(clp(total), style: mono(size: 16, color: CatalogColors.naranja)),
                ],
              ),
            ),
          );
        }
        final item = items[i - 1];
        if (item is DateTime) {
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6, left: 2),
            child: Text(
              encabezadoDia(item, hoy),
              style: TextStyle(fontSize: 13.5, color: CatalogColors.acero, fontWeight: FontWeight.w700),
            ),
          );
        }
        return Padding(
          // La primera compra de la lista se ilumina en la guía.
          key: i == 2 ? clavePrimera : null,
          padding: const EdgeInsets.only(bottom: 8),
          child: CompraTile(compra: item as Compra),
        );
      },
    );
  }
}
