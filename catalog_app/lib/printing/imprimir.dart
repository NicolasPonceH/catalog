import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../data/dispositivo.dart';
import '../features/ajustes_screen.dart';
import '../i18n.dart';
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
