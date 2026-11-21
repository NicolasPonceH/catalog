import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../domain/tipos.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';

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

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de compras')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
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
                  return _Lista(compras: lista);
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
  const _Lista({required this.compras});

  final List<Compra> compras;

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
                style: const TextStyle(fontSize: 14, color: CatalogColors.acero, fontWeight: FontWeight.w500)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: CompraTile(compra: item as Compra),
        );
      },
    );
  }
}
