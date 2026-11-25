import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'lote_screen.dart';

/// Lista de lotes escaneados.
class LotesScreen extends StatefulWidget {
  const LotesScreen({super.key});

  @override
  State<LotesScreen> createState() => _LotesScreenState();
}

class _LotesScreenState extends State<LotesScreen> {
  // Partes que ilumina la guía.
  final _gNuevo = GlobalKey();
  final _gLista = GlobalKey();

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gLista,
          icono: Icons.inventory_2_outlined,
          titulo: tr('Tus lotes', 'Your batches'),
          texto: tr(
            'Un lote junta varios catalíticos escaneados, por ejemplo los que entregas juntos. Cada uno muestra cuántos tiene, su estado y cuánto pagaste por ellos. Toca uno para abrirlo.',
            'A batch groups several scanned converters together, such as a shipment to the smelter. Each card shows its count, status, and total paid. Tap one to open it.',
          ),
        ),
        PasoGuia(
          clave: _gNuevo,
          icono: Icons.qr_code_scanner,
          titulo: tr('Nuevo lote', 'New batch'),
          texto: tr(
            'Le pones un nombre (viene sugerido con la fecha) y escaneas los stickers uno tras otro. Si sales sin escanear nada, el lote no se guarda.',
            'Give it a name (pre-filled with today’s date) and scan stickers one after another. Leaving an empty batch discards it automatically.',
          ),
        ),
      ]);

  /// Pide el nombre apenas se crea el lote (sugiere la fecha y hora).
  Future<void> _nuevo(BuildContext context) async {
    final sugerido = '${tr('Lote', 'Batch')} ${fechaHora(DateTime.now())}';
    final control = TextEditingController(text: sugerido)
      ..selection = TextSelection(baseOffset: 0, extentOffset: sugerido.length);
    final nombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Nuevo lote', 'New batch')),
        content: TextField(
          controller: control,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: tr('Nombre del lote', 'Batch name'),
            hintText: tr('Entrega a fundición', 'Smelter delivery'),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: () => Navigator.pop(context, control.text),
            child: Text(tr('Crear', 'Create')),
          ),
        ],
      ),
    );
    control.dispose();
    if (nombre == null || !context.mounted) return;
    final lote = await AppScope.of(context).lotes.crear(nombre: nombre.trim().isEmpty ? sugerido : nombre);
    if (context.mounted) await abrir(context, LoteScreen(loteId: lote.id, nuevo: true));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).lotes;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lotes escaneados', 'Scanned batches')),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: _gNuevo,
        onPressed: () => _nuevo(context),
        backgroundColor: CatalogColors.naranja,
        foregroundColor: CatalogColors.marino,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(tr('Nuevo lote', 'New batch')),
      ),
      body: SafeArea(
        child: Consulta<List<LoteConTotal>>(
          cargar: repo.listar,
          builder: (context, lista) {
            if (lista == null) return const Center(child: CircularProgressIndicator());
            if (lista.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    key: _gLista,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: CatalogColors.naranjaClara,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(Icons.inventory_2_outlined, color: CatalogColors.naranja),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            tr('Aún no tienes lotes escaneados', 'No scanned batches yet'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(
                              'Un lote junta varios catalíticos escaneados, por ejemplo los que entregas juntos. CataLog suma lo que pagaste por ellos y te arma el Excel.\n\nToca "Nuevo lote" y escanea los stickers uno tras otro.',
                              'A batch groups several scanned converters together, such as units delivered together. CataLog adds up what you paid and generates an Excel file.\n\nTap "New batch" and scan stickers one after another.',
                            ),
                            style: TextStyle(fontSize: 14.5, height: 1.45, color: CatalogColors.acero),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            final abiertos = lista.where((l) => !l.lote.cerrado).length;
            final piezas = lista.fold<int>(0, (s, l) => s + l.resumen.cantidad);
            final suma = lista.fold<int>(0, (s, l) => s + l.resumen.total);
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
              itemCount: lista.length + 1,
              itemBuilder: (context, idx) {
                if (idx == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                      decoration: BoxDecoration(
                        color: CatalogColors.marino,
                        borderRadius: BorderRadius.circular(18),
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
                                  '${lista.length} ${lista.length == 1 ? tr('lote', 'batch') : tr('lotes', 'batches')}'
                                  ' · ${contarCataliticos(piezas)}',
                                  style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(clp(suma), style: mono(size: 26, color: CatalogColors.naranja)),
                                ),
                              ],
                            ),
                          ),
                          if (abiertos > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: CatalogColors.naranja.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                tr(
                                  '$abiertos ${abiertos == 1 ? 'abierto' : 'abiertos'}',
                                  '$abiertos open',
                                ),
                                style: const TextStyle(
                                  color: CatalogColors.naranja,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                final i = idx - 1;
                final l = lista[i];
                final abierto = !l.lote.cerrado;
                final ganancia = l.ganancia;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    key: i == 0 ? _gLista : null,
                    shape: abierto
                        ? RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: CatalogColors.naranja, width: 1.8),
                          )
                        : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => abrir(context, LoteScreen(loteId: l.lote.id)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: abierto ? CatalogColors.naranja : const Color(0xFF5F7A8A),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                abierto ? Icons.inventory_2 : Icons.inventory_2_outlined,
                                color: abierto ? CatalogColors.marino : Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          l.lote.nombre,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(clp(l.resumen.total), style: mono(size: 15)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: abierto
                                              ? CatalogColors.verde.withValues(alpha: 0.15)
                                              : CatalogColors.borde.withValues(alpha: 0.55),
                                          borderRadius: BorderRadius.circular(99),
                                        ),
                                        child: Text(
                                          abierto ? tr('Abierto', 'Open') : tr('Cerrado', 'Closed'),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: abierto ? CatalogColors.verde : CatalogColors.acero,
                                          ),
                                        ),
                                      ),
                                      if (abierto)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: CatalogColors.naranja.withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.warning_amber_rounded, size: 12, color: CatalogColors.naranja),
                                              const SizedBox(width: 3),
                                              Text(
                                                tr('Falta cerrar', 'Needs closing'),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: CatalogColors.naranja,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (ganancia != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (ganancia >= 0 ? CatalogColors.verde : CatalogColors.rojo)
                                                .withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            '${tr('Utilidad', 'Profit')} ${ganancia >= 0 ? '+' : ''}${clp(ganancia)}',
                                            style: mono(
                                              size: 11,
                                              weight: FontWeight.w700,
                                              color: ganancia >= 0 ? CatalogColors.verde : CatalogColors.rojo,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        '${contarCataliticos(l.resumen.cantidad)} · ${fechaHora(l.lote.creadoEn)}',
                                        style: etiqueta,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
