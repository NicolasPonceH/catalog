import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../reports/excel.dart';
import '../system/confirmar.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/escaner_vista.dart';

/// Un lote: se escanean stickers seguidos y se suma lo pagado.
class LoteScreen extends StatefulWidget {
  const LoteScreen({super.key, required this.loteId, this.nuevo = false});

  final int loteId;

  /// Lote recién creado: si se sale sin escanear nada, no se guarda.
  final bool nuevo;

  @override
  State<LoteScreen> createState() => _LoteScreenState();
}

class _LoteScreenState extends State<LoteScreen> {
  String? _ultimoMensaje;
  bool _ultimoBien = true;
  LotesRepo? _repo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = AppScope.of(context).lotes;
  }

  /// Al salir de un lote nuevo sin catalíticos, se borra (no queda vacío en la lista).
  Future<void> _descartarSiVacio() async {
    final repo = _repo;
    if (!widget.nuevo || repo == null) return;
    try {
      if ((await repo.items(widget.loteId)).isEmpty) await repo.eliminar(widget.loteId);
    } catch (_) {}
  }

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
    if (ok != true || !mounted) return;
    if (!await confirmarConHuella(context, 'Confirma para borrar el lote')) return;
    if (!mounted) return;
    final navegador = Navigator.of(context);
    await AppScope.of(context).lotes.eliminar(lote.id);
    navegador.pop();
  }

  /// Terminar: si no se escaneó nada, el lote no se guarda.
  Future<void> _terminar(Lote lote) async {
    final repo = AppScope.of(context).lotes;
    if ((await repo.items(lote.id)).isEmpty) {
      await repo.eliminar(lote.id);
      if (!mounted) return;
      avisar(context, 'El lote estaba vacío y no se guardó');
      Navigator.of(context).pop();
      return;
    }
    await repo.cerrar(lote.id);
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
    if (!mounted) return;
    // La línea de estado no debe seguir diciendo "Agregado …" de lo que se acaba de quitar.
    setState(() {
      _ultimoMensaje = '${item.compra.codigo} quitado del lote';
      _ultimoBien = true;
    });
    avisar(context, '${item.compra.codigo} quitado del lote');
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).lotes;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _descartarSiVacio();
      },
      child: Consulta<Lote?>(
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
            child: LayoutBuilder(builder: (context, limites) {
              final escaner = Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: EscanerVista(alLeer: _leido),
              );
              final mensaje = _ultimoMensaje == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Row(
                        children: [
                          Icon(_ultimoBien ? Icons.check_circle : Icons.error,
                              color: _ultimoBien ? CatalogColors.verde : CatalogColors.rojo, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_ultimoMensaje!, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    );
              final resumen = Padding(
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
                );
              final lista = Consulta<List<ItemLote>>(
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
                            confirmDismiss: (_) =>
                                confirmarConHuella(context, 'Confirma para quitar ${items[i].compra.codigo} del lote'),
                            onDismissed: (_) => _quitar(items[i]),
                            child: CompraTile(compra: items[i].compra),
                          ),
                        ),
                      );
                    },
                  );
              final botones = Padding(
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
                          onPressed: lote.cerrado ? null : () => _terminar(lote),
                          icon: const Icon(Icons.done_all),
                          label: Text(lote.cerrado ? 'Lote cerrado' : 'Terminar'),
                        ),
                      ),
                    ],
                  ),
                );

              // Teléfono de lado o tablet: cámara a la izquierda, lista a la derecha.
              if (!lote.cerrado && limites.maxWidth > limites.maxHeight) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: Column(children: [Expanded(child: escaner), mensaje, const SizedBox(height: 12)])),
                    Expanded(flex: 6, child: Column(children: [resumen, Expanded(child: lista), botones])),
                  ],
                );
              }
              final altoEscaner = (limites.maxHeight * 0.36).clamp(160.0, 240.0);
              return Column(
                children: [
                  if (!lote.cerrado) ...[SizedBox(height: altoEscaner, child: escaner), mensaje],
                  resumen,
                  Expanded(child: lista),
                  botones,
                ],
              );
            }),
          ),
        );
      },
      ),
    );
  }
}
