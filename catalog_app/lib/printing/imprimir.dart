import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../features/ajustes_screen.dart';
import 'escpos.dart';
import 'etiqueta.dart';
import 'impresora.dart';
import 'raster.dart';

const claveImpresoraMac = 'impresora_mac';
const claveImpresoraNombre = 'impresora_nombre';
const claveAnchoPapel = 'ancho_papel';

/// Imprime un sticker con la impresora elegida en Ajustes.
/// Si se indica [compraId], suma una impresión a esa compra.
Future<bool> imprimirSticker(BuildContext context, DatosEtiqueta datos, {int? compraId}) async {
  final repo = AppScope.of(context).compras;
  final mac = await repo.leerAjuste(claveImpresoraMac);
  if (!context.mounted) return false;
  if (mac == null) {
    avisar(context, 'Primero elige la impresora en Ajustes');
    await abrir(context, const AjustesScreen());
    return false;
  }
  final ancho = (await repo.leerAjuste(claveAnchoPapel)) == '80' ? 576 : 384;
  if (!context.mounted) return false;
  avisar(context, 'Imprimiendo sticker…');
  try {
    final mono = await aMonocromo(await renderizarEtiqueta(datos, anchoPx: ancho));
    await Impresora.imprimir(mac, trabajoImpresion(mono));
    if (compraId != null) await repo.marcarImpresion(compraId);
    if (context.mounted) avisar(context, 'Sticker enviado a la impresora');
    return true;
  } on ErrorImpresora catch (e) {
    if (context.mounted) avisar(context, e.mensaje);
  } catch (e) {
    if (context.mounted) avisar(context, 'No se pudo imprimir: $e');
  }
  return false;
}

/// Comparte el sticker como imagen PNG (por si se imprime con otra app).
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
