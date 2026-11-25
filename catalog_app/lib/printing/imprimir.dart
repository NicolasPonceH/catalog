import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../data/dispositivo.dart';
import '../features/ajustes_screen.dart';
import '../i18n.dart';
import '../theme.dart';
import 'etiqueta.dart';
import 'impresora.dart';
import 'raster.dart';

/// Imprime un sticker con la impresora elegida en Ajustes (es la misma en todas
/// las sesiones). Si se indica [compraId], suma una impresión a esa compra.
Future<bool> imprimirSticker(BuildContext context, DatosEtiqueta datos, {int? compraId}) async {
  final scope = AppScope.of(context);
  final dispositivo = scope.dispositivo;
  final impresora = ImpresoraGuardada.deTexto(dispositivo?.leer(AjustesDispositivo.impresora));
  if (impresora == null) {
    avisar(context, tr('Primero elige la impresora en Ajustes', 'First choose a printer in Settings'));
    await abrir(context, const AjustesScreen());
    return false;
  }
  final ancho80 = dispositivo?.leer(AjustesDispositivo.anchoPapel) == '80' && !impresora.soloAnchoChico;
  avisar(context, tr('Imprimiendo sticker…', 'Printing sticker…'));
  try {
    final mono = await aMonocromo(await renderizarEtiqueta(datos, anchoPx: ancho80 ? 576 : 384));
    await Impresora.imprimir(impresora, mono);
    if (compraId != null && !scope.soloLectura) await scope.compras.marcarImpresion(compraId);
    if (context.mounted) avisar(context, tr('Sticker enviado a la impresora', 'Sticker sent to printer'));
    return true;
  } on ErrorImpresora catch (e) {
    if (context.mounted) avisar(context, e.mensaje);
  } catch (e) {
    if (context.mounted) avisar(context, '${tr('No se pudo imprimir', 'Could not print')}: $e');
  }
  return false;
}

/// Comparte el sticker como imagen PNG: sirve para imprimirlo con la app
/// propia de cualquier impresora.
Future<void> compartirSticker(DatosEtiqueta datos) async {
  final png = await pngDeMonocromo(await aMonocromo(await renderizarEtiqueta(datos, anchoPx: 576)));
  final dir = await getTemporaryDirectory();
  final archivo = File(p.join(dir.path, 'sticker-${datos.codigo}.png'));
  await archivo.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(archivo.path, mimeType: 'image/png')],
    text: datos.codigo,
  ));
}

/// Imprime en la térmica Bluetooth la Etiqueta Maestra QR del Saco / Caja.
Future<bool> imprimirEtiquetaLote(BuildContext context, DatosEtiquetaLote datos) async {
  final scope = AppScope.of(context);
  final dispositivo = scope.dispositivo;
  final impresora = ImpresoraGuardada.deTexto(dispositivo?.leer(AjustesDispositivo.impresora));
  if (impresora == null) {
    avisar(context, tr('Primero elige la impresora en Ajustes', 'First choose a printer in Settings'));
    await abrir(context, const AjustesScreen());
    return false;
  }
  final ancho80 = dispositivo?.leer(AjustesDispositivo.anchoPapel) == '80' && !impresora.soloAnchoChico;
  avisar(context, tr('Imprimiendo etiqueta del saco…', 'Printing bag label…'));
  try {
    final mono = await aMonocromo(await renderizarEtiquetaLote(datos, anchoPx: ancho80 ? 576 : 384));
    await Impresora.imprimir(impresora, mono);
    if (context.mounted) avisar(context, tr('Etiqueta de lote enviada a la impresora', 'Batch label sent to printer'));
    return true;
  } on ErrorImpresora catch (e) {
    if (context.mounted) avisar(context, e.mensaje);
  } catch (e) {
    if (context.mounted) avisar(context, '${tr('No se pudo imprimir', 'Could not print')}: $e');
  }
  return false;
}

/// Comparte la Etiqueta Maestra QR del lote como imagen PNG.
Future<void> compartirEtiquetaLote(DatosEtiquetaLote datos) async {
  final png = await pngDeMonocromo(await aMonocromo(await renderizarEtiquetaLote(datos, anchoPx: 576)));
  final dir = await getTemporaryDirectory();
  final archivo = File(p.join(dir.path, 'etiqueta-${datos.codigoLote}.png'));
  await archivo.writeAsBytes(png, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(archivo.path, mimeType: 'image/png')],
    text: '${datos.nombreLote} (${datos.codigoLote})',
  ));
}

/// Muestra la vista previa exacta de la Etiqueta Maestra QR del Saco / Caja con
/// botones para imprimir en Bluetooth o compartir como imagen.
Future<void> mostrarDialogoEtiquetaLote(BuildContext context, DatosEtiquetaLote datos) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Etiqueta QR para el Saco / Caja', 'Master QR Label for Bag / Box'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                'Pégala por fuera del saco o caja. Después puedes escanearla desde el botón central «Escanear», en «Lotes» o dentro de «Revisión de Supervisor» para abrir o auditar el saco.',
                'Stick it outside the bag or box. Scan it anytime from the central "Scan" button, in "Batches", or inside "Supervisor Review" to open or audit this bag.',
              ),
              style: etiqueta.copyWith(height: 1.35),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: EtiquetaLoteVista(datos: datos),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => imprimirEtiquetaLote(context, datos),
              icon: const Icon(Icons.print_outlined),
              label: Text(tr('Imprimir etiqueta en Bluetooth', 'Print label via Bluetooth')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await compartirEtiquetaLote(datos);
                } catch (e) {
                  if (ctx.mounted) avisar(ctx, '${tr('No se pudo compartir', 'Could not share')}: $e');
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: Text(tr('Compartir etiqueta como imagen', 'Share label as image')),
            ),
          ],
        ),
      ),
    ),
  );
}
