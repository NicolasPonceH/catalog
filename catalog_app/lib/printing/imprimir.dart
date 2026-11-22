import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../features/ajustes_screen.dart';
import 'etiqueta.dart';
import 'impresora.dart';
import 'raster.dart';

const claveImpresora = 'impresora';
const claveAnchoPapel = 'ancho_papel';

/// Imprime un sticker con la impresora elegida en Ajustes.
/// Si se indica [compraId], suma una impresión a esa compra.
Future<bool> imprimirSticker(BuildContext context, DatosEtiqueta datos, {int? compraId}) async {
  final repo = AppScope.of(context).compras;
  final impresora = ImpresoraGuardada.deTexto(await repo.leerAjuste(claveImpresora));
  if (!context.mounted) return false;
  if (impresora == null) {
    avisar(context, 'Primero elige la impresora en Ajustes');
    await abrir(context, const AjustesScreen());
    return false;
  }
  final ancho80 = (await repo.leerAjuste(claveAnchoPapel)) == '80' && !impresora.soloAnchoChico;
  if (!context.mounted) return false;
  avisar(context, 'Imprimiendo sticker…');
  try {
    final mono = await aMonocromo(await renderizarEtiqueta(datos, anchoPx: ancho80 ? 576 : 384));
    await Impresora.imprimir(impresora, mono);
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
