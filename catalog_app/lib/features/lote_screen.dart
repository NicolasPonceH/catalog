import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../reports/excel.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/escaner_vista.dart';

/// Un lote: se escanean stickers seguidos y se suma lo pagado.
class LoteScreen extends StatefulWidget {
  const LoteScreen({super.key, required this.loteId});

  final int loteId;

  @override
  State<LoteScreen> createState() => _LoteScreenState();
}

class _LoteScreenState extends State<LoteScreen> {
  String? _ultimoMensaje;
  bool _ultimoBien = true;

  Future<void> _leido(String texto) async {
    final repo = AppScope.of(context).lotes;
    final (resultado, compra) = await repo.agregarEscaneado(widget.loteId, texto);
    if (!mounted) return;
    final codigo = compra?.codigo ?? texto;
    final (mensaje, bien) = switch (resultado) {
      ResultadoEscaneo.agregado => ('Agregado $codigo · ${clp(compra!.precio)}', true),
      ResultadoEscaneo.yaEstaba => ('$codigo ya estaba en el lote', true),
      ResultadoEscaneo.anulada => ('$codigo es una compra anulada: no se agrega', false),
      ResultadoEscaneo.noExiste => ('$codigo no está registrado en este teléfono', false),
      ResultadoEscaneo.noEsCodigo => ('Ese código no es de CataLog', false),
    };
    if (resultado == ResultadoEscaneo.agregado) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    } else if (!bien) {
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _ultimoMensaje = mensaje;
      _ultimoBien = bien;
    });
  }

  Future<void> _manual() async {
    final t = await pedirCodigoManual(context);
    if (t != null && t.trim().isNotEmpty) await _leido(t);
  }

  Future<void> _renombrar(Lote lote) async {
    final control = TextEditingController(text: lote.nombre);
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del lote'),
        content: TextField(
          controller: control,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Entrega a fundición'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, control.text), child: const Text('Guardar')),
        ],
      ),
    );
    control.dispose();
    if (nombre != null && mounted) await AppScope.of(context).lotes.renombrar(lote.id, nombre);
  }

  Future<void> _eliminar(Lote lote) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar este lote?'),
        content: const Text('Se borra solo la agrupación. Las compras siguen registradas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Borrar lote')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final navegador = Navigator.of(context);
      await AppScope.of(context).lotes.eliminar(lote.id);
      navegador.pop();
    }
  }

  Future<void> _exportar(Lote lote) async {
    final scope = AppScope.of(context);
    try {
      final items = await scope.lotes.items(lote.id);
      if (items.isEmpty) {
        if (mounted) avisar(context, 'El lote todavía no tiene catalíticos');
        return;
      }
      final comprador = await scope.compras.leerAjuste('nombre') ?? '';
      final total = items.where((i) => !i.compra.anulada).fold<int>(0, (s, i) => s + i.compra.precio);
      await compartirExcel(
        excelDeLote(lote, items, comprador: comprador),
        'CataLog ${lote.nombre}.xlsx',
        texto: '${lote.nombre} · ${items.length} catalíticos · ${clp(total)}',
      );
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo crear el Excel: $e');
    }
  }

  Future<void> _quitar(ItemLote item) async {
    await AppScope.of(context).lotes.quitar(widget.loteId, item.compra.id);
    if (mounted) avisar(context, '${item.compra.codigo} quitado del lote');
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).lotes;
    return Consulta<Lote?>(
      claves: [widget.loteId],
      cargar: () => repo.obtener(widget.loteId),
      builder: (context, lote) {
        if (lote == null) {
          return Scaffold(appBar: AppBar(title: const Text('Lote')), body: const SizedBox());
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(lote.nombre, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Exportar a Excel',
                icon: const Icon(Icons.table_view_outlined),
                onPressed: () => _exportar(lote),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'renombrar' => _renombrar(lote),
                  'reabrir' => repo.reabrir(lote.id),
                  'eliminar' => _eliminar(lote),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'renombrar', child: Text('Cambiar nombre')),
                  if (lote.cerrado) const PopupMenuItem(value: 'reabrir', child: Text('Seguir escaneando')),
                  const PopupMenuItem(value: 'eliminar', child: Text('Borrar lote')),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (!lote.cerrado) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SizedBox(height: 220, child: EscanerVista(alLeer: _leido)),
                  ),
                  if (_ultimoMensaje != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        children: [
                          Icon(_ultimoBien ? Icons.check_circle : Icons.error,
                              color: _ultimoBien ? CatalogColors.verde : CatalogColors.rojo, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_ultimoMensaje!, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Consulta<Resumen>(
                    claves: [lote.id],
                    cargar: () => repo.resumen(lote.id),
                    builder: (context, r) {
                      r ??= Resumen.vacio;
                      return Card(
                        color: CatalogColors.marino,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${r.cantidad} ${r.cantidad == 1 ? 'catalítico' : 'catalíticos'}',
                                  style: const TextStyle(color: CatalogColors.niebla, fontSize: 16),
                                ),
                              ),
                              Text(clp(r.total), style: mono(size: 24, color: CatalogColors.naranja)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: Consulta<List<ItemLote>>(
                    claves: [lote.id],
                    cargar: () => repo.items(lote.id),
                    builder: (context, items) {
                      if (items == null) return const SizedBox();
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Escanea los stickers uno tras otro. Cada uno suma su precio.',
                              style: TextStyle(fontSize: 15, color: CatalogColors.acero)),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: items.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: ValueKey(items[i].compra.id),
                            direction: lote.cerrado ? DismissDirection.none : DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              child: const Icon(Icons.remove_circle_outline, color: CatalogColors.rojo),
                            ),
                            onDismissed: (_) => _quitar(items[i]),
                            child: CompraTile(compra: items[i].compra),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      if (!lote.cerrado)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _manual,
                            icon: const Icon(Icons.keyboard_outlined),
                            label: const Text('A mano'),
                          ),
                        ),
                      if (!lote.cerrado) const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: lote.cerrado ? null : () => repo.cerrar(lote.id),
                          icon: const Icon(Icons.done_all),
                          label: Text(lote.cerrado ? 'Lote cerrado' : 'Terminar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
