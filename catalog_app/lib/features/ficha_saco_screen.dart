import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/base.dart';
import '../data/lotes_repo.dart';
import '../data/sesiones.dart';
import '../data/supervisor_repo.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import '../printing/etiqueta.dart';
import '../printing/imprimir.dart';
import '../reports/excel.dart';
import '../theme.dart';
import 'revision_supervisor_screen.dart';
import 'traspaso.dart';

/// Ficha completa que se abre al escanear la Etiqueta Maestra QR o código de barras
/// de un saco / caja (`LOT-...` de comprador recibido o `SUP-...` de supervisor).
class FichaSacoScreen extends StatefulWidget {
  const FichaSacoScreen({
    super.key,
    required this.escaneado,
    this.loteSupervisor,
    this.itemsSupervisor,
    this.sesionComprador,
    this.loteComprador,
    this.itemsComprador,
  });

  final CodigoLoteEscaneado escaneado;
  final LoteSupervisor? loteSupervisor;
  final List<ItemLoteSupervisor>? itemsSupervisor;
  final Sesion? sesionComprador;
  final Lote? loteComprador;
  final List<ItemLote>? itemsComprador;

  /// Busca los datos completos del saco escaneado en la base local y en las
  /// sesiones recibidas de compradores, y devuelve la pantalla lista para mostrar.
  static Future<FichaSacoScreen> resolver({
    required AppScope scope,
    required CodigoLoteEscaneado escaneado,
  }) async {
    if (escaneado.esSupervisor) {
      final loteSup = await scope.supervisor.obtenerLote(escaneado.loteId);
      if (loteSup != null && diaClave(loteSup.cerradoEn) == escaneado.dia) {
        final items = await scope.supervisor.itemsDeLote(loteSup.id);
        return FichaSacoScreen(
          escaneado: escaneado,
          loteSupervisor: loteSup,
          itemsSupervisor: items,
        );
      }
      return FichaSacoScreen(escaneado: escaneado);
    }

    // Buscar el saco en las sesiones de compradores recibidas por WhatsApp / Wi-Fi.
    final sesiones = scope.sesiones;
    if (sesiones != null && sesiones.documentos.existsSync()) {
      final revs = await sesiones.revisiones();
      for (final rev in revs) {
        CatalogDb? db;
        try {
          db = await CatalogDb.abrir(ruta: rev.rutaBase);
          final repoLotes = LotesRepo(db);
          final lote = await repoLotes.obtener(escaneado.loteId);
          if (lote != null) {
            final f = lote.cerradoEn ?? lote.creadoEn;
            if (diaClave(f) == escaneado.dia) {
              final items = await repoLotes.items(lote.id);
              await db.cerrar();
              return FichaSacoScreen(
                escaneado: escaneado,
                sesionComprador: rev,
                loteComprador: lote,
                itemsComprador: items,
              );
            }
          }
        } catch (_) {
        } finally {
          try {
            await db?.cerrar();
          } catch (_) {}
        }
      }
    }
    return FichaSacoScreen(escaneado: escaneado);
  }

  @override
  State<FichaSacoScreen> createState() => _FichaSacoScreenState();
}

class _FichaSacoScreenState extends State<FichaSacoScreen> {
  Future<void> _exportarExcelSup(LoteSupervisor lote, List<ItemLoteSupervisor> items) async {
    final filas = items.map(FilaRevisionExcel.deItemLoteSupervisor).toList();
    final bytes = excelDeRevisionSupervisor(
      filas,
      titulo: lote.nombre,
      comprador: lote.comprador,
      prefijo: lote.prefijo,
      rangoFechas: lote.rangoTexto,
    );
    await compartirExcel(
      bytes,
      '${lote.codigoLote}-${lote.nombre}.xlsx',
      texto: '${lote.nombre} · ${contarCataliticos(lote.cantidad)} · ${clp(lote.totalVerificado)}',
    );
  }

  Future<void> _reimprimirSup(LoteSupervisor lote, List<ItemLoteSupervisor> items) async {
    var cer = 0, met = 0, dpf = 0;
    for (final it in items) {
      final t = it.tipo.toLowerCase();
      if (t.contains('dpf')) {
        dpf++;
      } else if (t.contains('met')) {
        met++;
      } else {
        cer++;
      }
    }
    final datos = DatosEtiquetaLote(
      codigoLote: lote.codigoLote,
      nombreLote: lote.nombre,
      fecha: lote.cerradoEn,
      totalPiezas: items.length,
      ceramicos: cer,
      metalicos: met,
      dpf: dpf,
      conObservacion: lote.conObservacion,
      responsable: [if (lote.comprador.isNotEmpty) lote.comprador, if (lote.prefijo.isNotEmpty) lote.prefijo].join(' · '),
      esSupervisor: true,
    );
    await mostrarDialogoEtiquetaLote(context, datos);
  }

  @override
  Widget build(BuildContext context) {
    final esc = widget.escaneado;
    final sup = widget.loteSupervisor;
    final itemsSup = widget.itemsSupervisor;
    final loteComp = widget.loteComprador;
    final itemsComp = widget.itemsComprador;
    final revComp = widget.sesionComprador;

    final titulo = sup?.nombre ??
        loteComp?.nombre ??
        (esc.nombreLote.isNotEmpty ? esc.nombreLote : tr('Saco / Lote escaneado', 'Scanned Bag / Batch'));

    final totalPiezas = sup?.cantidad ?? itemsComp?.length ?? esc.totalPiezas ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo, overflow: TextOverflow.ellipsis),
        actions: [
          if (sup != null && itemsSup != null) ...[
            IconButton(
              tooltip: tr('Etiqueta QR del saco', 'Master QR bag label'),
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => _reimprimirSup(sup, itemsSup),
            ),
            IconButton(
              tooltip: 'Excel',
              icon: const Icon(Icons.table_view_outlined),
              onPressed: () => _exportarExcelSup(sup, itemsSup),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            // Tarjeta principal del saco
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CatalogColors.marino,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: CatalogColors.naranja,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          esc.esSupervisor
                              ? tr('LOTE SUPERVISOR', 'SUPERVISOR BATCH')
                              : tr('SACO DE COMPRADOR', 'BUYER BAG'),
                          style: const TextStyle(
                            color: CatalogColors.marino,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        esc.codigoLote,
                        style: mono(size: 13.5, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    titulo,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        contarCataliticos(totalPiezas),
                        style: mono(size: 21, weight: FontWeight.w700, color: CatalogColors.naranja),
                      ),
                      if (sup != null) ...[
                        const Spacer(),
                        Text(
                          clp(sup.totalVerificado),
                          style: mono(size: 20, weight: FontWeight.w700, color: const Color(0xFF42E39B)),
                        ),
                      ] else if (itemsComp != null) ...[
                        const Spacer(),
                        Text(
                          clp(itemsComp.where((i) => !i.compra.anulada).fold<int>(0, (s, i) => s + i.compra.precio)),
                          style: mono(size: 20, weight: FontWeight.w700, color: const Color(0xFF42E39B)),
                        ),
                      ],
                    ],
                  ),
                  if (esc.ceramicos != null || esc.metalicos != null || esc.dpf != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${tr('Cerámico', 'Ceramic')}: ${esc.ceramicos ?? 0} · '
                      '${tr('Metálico', 'Metallic')}: ${esc.metalicos ?? 0} · '
                      'DPF: ${esc.dpf ?? 0}',
                      style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 13),
                    ),
                  ],
                  if (esc.responsable.isNotEmpty || revComp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      revComp?.nombre ?? '${tr('Origen', 'Origin')}: ${esc.responsable}',
                      style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),

            // Acción principal cuando es un saco de comprador recibido en el celular del supervisor
            if (revComp != null && loteComp != null && itemsComp != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: CatalogColors.naranja,
                  foregroundColor: CatalogColors.marino,
                ),
                onPressed: () {
                  final codigos = {for (final i in itemsComp) i.compra.codigo};
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => RevisionSupervisorScreen(
                        revisionInicial: revComp,
                        codigosFiltroInicial: codigos,
                        tituloFiltroSaco: '${loteComp.nombre} (${esc.codigoLote})',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.fact_check_outlined),
                label: Text(
                  tr('Auditar las piezas de este saco con escáner', 'Audit this bag’s units with scanner'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr('Catalíticos dentro de este saco', 'Converters inside this bag'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final it in itemsComp)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      dense: true,
                      title: Text(it.compra.codigo, style: mono(size: 13.5, weight: FontWeight.w700)),
                      subtitle: Text('${it.compra.vendedor} · ${it.compra.tipoConLlenado}'),
                      trailing: Text(clp(it.compra.precio), style: mono(size: 14)),
                    ),
                  ),
                ),
            ]
            // Contenido de un Lote de Supervisor propio
            else if (sup != null && itemsSup != null) ...[
              const SizedBox(height: 14),
              Text(
                tr('Catalíticos verificados en este lote', 'Verified converters in this batch'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final it in itemsSup)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: it.observacion.activa ? CatalogColors.rojo : CatalogColors.verde.withValues(alpha: 0.65),
                        width: 1.4,
                      ),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(it.codigo, style: mono(size: 13.5, weight: FontWeight.w700)),
                      subtitle: Text(
                        [
                          if (it.vendedor.isNotEmpty) it.vendedor,
                          if (it.tipo.isNotEmpty) it.tipo,
                          it.llenado.etiqueta,
                          if (it.observacion.activa) '⚠ ${it.observacion.resumen}',
                        ].join(' · '),
                        style: TextStyle(
                          color: it.observacion.activa ? CatalogColors.rojo : CatalogColors.acero,
                          fontWeight: it.observacion.activa ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                      trailing: Text(clp(it.precio), style: mono(size: 14)),
                    ),
                  ),
                ),
            ]
            // Saco escaneado en otro teléfono que aún no ha cargado el .zip / Wi-Fi de ese comprador
            else ...[
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, color: CatalogColors.naranja),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr('Resumen leído desde el QR del saco', 'Summary read from the bag’s QR label'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr(
                          'Para ver y escanear uno por uno los catalíticos que vienen adentro de este saco (con sus fotos y precios), recibe primero el envío de esas fechas por Wi-Fi o WhatsApp.',
                          'To inspect and scan each converter inside this bag (with photos and prices), receive that date’s package via Wi-Fi or WhatsApp first.',
                        ),
                        style: TextStyle(fontSize: 14, color: CatalogColors.acero, height: 1.4),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await sincronizarPorWifi(context, iniciarEnRecibir: true);
                        },
                        icon: const Icon(Icons.wifi_tethering),
                        label: Text(tr('Recibir datos por Wi-Fi', 'Receive data over Wi-Fi')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await recibirDatos(context);
                        },
                        icon: const Icon(Icons.folder_open_outlined),
                        label: Text(tr('Cargar archivo .zip de WhatsApp', 'Load WhatsApp .zip file')),
                      ),
                    ],
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
