import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../domain/tipos.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';

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

  // Partes que ilumina la guía.
  final _gBuscar = GlobalKey();
  final _gFiltros = GlobalKey();
  final _gResumen = GlobalKey();
  final _gPrimera = GlobalKey();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _mostrarGuia() {
    FocusManager.instance.primaryFocus?.unfocus();
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gBuscar,
        icono: Icons.search,
        titulo: 'Buscar',
        texto: 'Escribe parte del vendedor, el código, el auto, el lugar o el código de fábrica.',
      ),
      PasoGuia(
        clave: _gFiltros,
        icono: Icons.filter_list,
        titulo: 'Filtros',
        texto: 'Elige el período (hoy, semana, mes…) y el material. Desliza hacia el lado para ver más.',
      ),
      PasoGuia(
        clave: _gResumen,
        icono: Icons.functions,
        titulo: 'Total del filtro',
        texto: 'Cuántos catalíticos y cuánto pagaste por los que muestra la lista. Las anuladas no suman.',
      ),
      PasoGuia(
        clave: _gPrimera,
        icono: Icons.touch_app_outlined,
        titulo: 'Abrir una compra',
        texto: 'Las compras van por día de compra, de la más nueva a la más vieja. Toca una para ver su ficha.',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de compras'),
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
                  hintText: 'Buscar vendedor, código, auto o lugar',
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
                        onSelected: (_) => setState(() => _periodo = t),
                      ),
                    ),
                  const SizedBox(width: 10),
                  for (final m in TipoMaterial.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(m.etiqueta),
                        selected: _material == m,
                        onSelected: (s) => setState(() => _material = s ? m : null),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Consulta<List<Compra>>(
                claves: [_buscar.text, _periodo, _material],
                cargar: () => repo.historial(FiltroHistorial(
                  texto: _buscar.text,
                  periodo: periodoDe(_periodo, DateTime.now()),
                  material: _material,
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
    final activas = compras.where((c) => !c.anulada);
    final total = activas.fold<int>(0, (s, c) => s + c.precio);
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            key: claveResumen,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              compras.isEmpty
                  ? 'No hay compras con estos filtros.'
                  : '${activas.length} ${activas.length == 1 ? 'catalítico' : 'catalíticos'} · ${clp(total)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          );
        }
        final item = items[i - 1];
        if (item is DateTime) {
          return Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(encabezadoDia(item, hoy),
                style: TextStyle(fontSize: 14, color: CatalogColors.acero, fontWeight: FontWeight.w500)),
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
