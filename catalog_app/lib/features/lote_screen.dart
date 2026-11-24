import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../reports/excel.dart';
import '../system/confirmar.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/escaner_vista.dart';
import '../widgets/guia.dart';

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

  // Partes que ilumina la guía.
  final _gCamara = GlobalKey();
  final _gResumen = GlobalKey();
  final _gLista = GlobalKey();
  final _gMano = GlobalKey();
  final _gTerminar = GlobalKey();
  final _gExcel = GlobalKey();
  final _gMenu = GlobalKey();

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gCamara,
          icono: Icons.qr_code_scanner,
          titulo: tr('Escanea los stickers', 'Scan stickers'),
          texto: tr(
            'Apunta al QR o al código de barras, uno tras otro. Vibra con cada lectura y el mismo catalítico no se cuenta dos veces. Con poca luz, usa la linterna.',
            'Point at the QR code or barcode one after another. Vibrates on each scan and never counts the same converter twice. Use the flashlight in low light.',
          ),
        ),
        PasoGuia(
          clave: _gResumen,
          icono: Icons.functions,
          titulo: tr('Total del lote', 'Batch total'),
          texto: tr(
            'Cuántos catalíticos lleva el lote, el promedio por pieza y cuánto pagaste en total.',
            'How many converters are in the batch, average per unit, and total paid.',
          ),
        ),
        PasoGuia(
          clave: _gLista,
          icono: Icons.swipe_left_outlined,
          titulo: tr('Los catalíticos del lote', 'Converters in this batch'),
          texto: tr(
            'Toca uno para ver su ficha. Para quitarlo, deslízalo hacia la izquierda: pide tu huella.',
            'Tap any item to view its record. Swipe left to remove it from the batch (requires fingerprint).',
          ),
        ),
        PasoGuia(
          clave: _gMano,
          icono: Icons.keyboard_outlined,
          titulo: tr('Escribir a mano', 'Manual entry'),
          texto: tr(
            'Si un sticker está dañado y no se lee, escribe su código.',
            'If a sticker is damaged and won’t scan, type its code manually.',
          ),
        ),
        PasoGuia(
          clave: _gTerminar,
          icono: Icons.done_all,
          titulo: tr('Terminar', 'Finish'),
          texto: tr(
            'Cierra el lote. Si no escaneaste nada, no se guarda.',
            'Closes the batch. Empty batches are discarded automatically.',
          ),
        ),
        PasoGuia(
          clave: _gExcel,
          icono: Icons.table_view_outlined,
          titulo: tr('Excel del lote', 'Batch Excel'),
          texto: tr(
            'Arma el Excel con cada catalítico y el total, para mandarlo por WhatsApp o correo.',
            'Generates an Excel file with every converter and total paid, ready to share via WhatsApp or email.',
          ),
        ),
        PasoGuia(
          clave: _gMenu,
          icono: Icons.more_vert,
          titulo: tr('Más opciones', 'More options'),
          texto: tr(
            'Cambiar el nombre, seguir escaneando un lote cerrado o borrarlo (con huella).',
            'Rename the batch, reopen a closed batch to keep scanning, or delete it (with fingerprint).',
          ),
        ),
      ]);
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
      ResultadoEscaneo.agregado => ('${tr('Agregado', 'Added')} $codigo · ${clp(compra!.precio)}', true),
      ResultadoEscaneo.yaEstaba => (tr('$codigo ya estaba en el lote', '$codigo is already in this batch'), true),
      ResultadoEscaneo.anulada => (
          tr('$codigo es una compra anulada: no se agrega', '$codigo is a voided purchase: not added'),
          false,
        ),
      ResultadoEscaneo.noExiste => (
          tr('$codigo no está registrado en este teléfono', '$codigo is not registered on this phone'),
          false,
        ),
      ResultadoEscaneo.noEsCodigo => (tr('Ese código no es de CataLog', 'That code is not from CataLog'), false),
    };
    // Vibración y sonido, si están activados en Ajustes.
    final d = AppScope.of(context).dispositivo;
    final vibrar = d?.vibrar ?? true;
    if (resultado == ResultadoEscaneo.agregado) {
      if (vibrar) HapticFeedback.mediumImpact();
      if (d?.sonar ?? true) SystemSound.play(SystemSoundType.click);
    } else if (!bien && vibrar) {
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
        title: Text(tr('Nombre del lote', 'Batch name')),
        content: TextField(
          controller: control,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Entrega a fundición', 'Smelter delivery')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, control.text), child: Text(tr('Guardar', 'Save'))),
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
        title: Text(tr('¿Borrar este lote?', 'Delete this batch?')),
        content: Text(
          tr(
            'Se borra solo la agrupación. Las compras siguen registradas.',
            'Deletes only this batch grouping. Individual purchases remain saved.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Borrar lote', 'Delete batch'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await confirmarConHuella(context, tr('Confirma para borrar el lote', 'Confirm to delete batch'))) return;
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
      avisar(context, tr('El lote estaba vacío y no se guardó', 'Batch was empty and was discarded'));
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
        if (mounted) avisar(context, tr('El lote todavía no tiene catalíticos', 'This batch has no converters yet'));
        return;
      }
      final comprador = await scope.compras.leerAjuste('nombre') ?? '';
      final total = items.where((i) => !i.compra.anulada).fold<int>(0, (s, i) => s + i.compra.precio);
      await compartirExcel(
        excelDeLote(lote, items, comprador: comprador),
        'CataLog ${lote.nombre}.xlsx',
        texto: '${lote.nombre} · ${contarCataliticos(items.length)} · ${clp(total)}',
      );
    } catch (e) {
      if (mounted) avisar(context, '${tr('No se pudo crear el Excel', 'Could not create Excel')}: $e');
    }
  }

  Future<void> _quitar(ItemLote item) async {
    await AppScope.of(context).lotes.quitar(widget.loteId, item.compra.id);
    if (!mounted) return;
    // La línea de estado no debe seguir diciendo "Agregado …" de lo que se acaba de quitar.
    final msg = tr('${item.compra.codigo} quitado del lote', '${item.compra.codigo} removed from batch');
    setState(() {
      _ultimoMensaje = msg;
      _ultimoBien = true;
    });
    avisar(context, msg);
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
            return Scaffold(appBar: AppBar(title: Text(tr('Lote', 'Batch'))), body: const SizedBox());
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(lote.nombre, overflow: TextOverflow.ellipsis),
              actions: [
                BotonAyuda(alTocar: _mostrarGuia),
                IconButton(
                  key: _gExcel,
                  tooltip: tr('Exportar a Excel', 'Export to Excel'),
                  icon: const Icon(Icons.table_view_outlined),
                  onPressed: () => _exportar(lote),
                ),
                PopupMenuButton<String>(
                  key: _gMenu,
                  onSelected: (v) => switch (v) {
                    'renombrar' => _renombrar(lote),
                    'reabrir' => repo.reabrir(lote.id),
                    'eliminar' => _eliminar(lote),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'renombrar', child: Text(tr('Cambiar nombre', 'Rename'))),
                    if (lote.cerrado)
                      PopupMenuItem(value: 'reabrir', child: Text(tr('Seguir escaneando', 'Keep scanning'))),
                    PopupMenuItem(value: 'eliminar', child: Text(tr('Borrar lote', 'Delete batch'))),
                  ],
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(builder: (context, limites) {
                final escaner = Padding(
                  key: _gCamara,
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
                  key: _gResumen,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Consulta<Resumen>(
                    claves: [lote.id],
                    cargar: () => repo.resumen(lote.id),
                    builder: (context, r) {
                      r ??= Resumen.vacio;
                      return Container(
                        padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                        decoration: BoxDecoration(
                          color: CatalogColors.marino,
                          borderRadius: BorderRadius.circular(16),
                          border: CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1
                              ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    contarCataliticos(r.cantidad),
                                    style: const TextStyle(
                                        color: CatalogColors.niebla, fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                  if (r.cantidad > 0)
                                    Text(
                                      '${tr('promedio', 'avg')} ${clp(r.promedio)}',
                                      style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12.5),
                                    ),
                                ],
                              ),
                            ),
                            Text(clp(r.total), style: mono(size: 24, color: CatalogColors.naranja)),
                          ],
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
                      return Padding(
                        key: _gLista,
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          tr(
                            'Escanea los stickers uno tras otro. Cada uno suma su precio.',
                            'Scan stickers one after another. Each scan adds its purchase price.',
                          ),
                          style: TextStyle(fontSize: 15, color: CatalogColors.acero),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: items.length,
                      itemBuilder: (context, i) => Padding(
                        key: i == 0 ? _gLista : null,
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Dismissible(
                          key: ValueKey(items[i].compra.id),
                          direction: lote.cerrado ? DismissDirection.none : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: Icon(Icons.remove_circle_outline, color: CatalogColors.rojo),
                          ),
                          confirmDismiss: (_) => confirmarConHuella(
                            context,
                            tr(
                              'Confirma para quitar ${items[i].compra.codigo} del lote',
                              'Confirm to remove ${items[i].compra.codigo} from batch',
                            ),
                          ),
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
                            key: _gMano,
                            onPressed: _manual,
                            icon: const Icon(Icons.keyboard_outlined),
                            label: Text(tr('A mano', 'Manual')),
                          ),
                        ),
                      if (!lote.cerrado) const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          key: _gTerminar,
                          onPressed: lote.cerrado ? null : () => _terminar(lote),
                          icon: const Icon(Icons.done_all),
                          label: Text(lote.cerrado ? tr('Lote cerrado', 'Batch closed') : tr('Terminar', 'Finish')),
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
                      Expanded(
                          flex: 5,
                          child: Column(children: [Expanded(child: escaner), mensaje, const SizedBox(height: 12)])),
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
