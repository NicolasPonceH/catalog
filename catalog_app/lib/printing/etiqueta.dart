import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import '../data/compra.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../theme.dart';
import '../widgets/catalog_logo.dart';
import 'code128.dart';

/// Lo que va impreso en el sticker. El precio NO va.
class DatosEtiqueta {
  const DatosEtiqueta({required this.codigo, required this.fechaCompra, required this.tipo});

  factory DatosEtiqueta.deCompra(Compra c) =>
      DatosEtiqueta(codigo: c.codigo, fechaCompra: c.fechaCompra, tipo: c.tipo);

  final String codigo;
  final DateTime fechaCompra;
  final String tipo;
}

/// El sticker se diseña para 384 puntos de ancho (papel de 58 mm a 203 ppp).
/// Para papel de 80 mm se escala a 576 puntos.
const anchoEtiqueta = 384.0;
const altoEtiqueta = 378.0;

const _negro = Color(0xFF000000);
const _blanco = Color(0xFFFFFFFF);

/// Número de pieza del día, tomado del final del código (CTL-261121-0007 -> 7).
int? _piezaDelDia(String codigo) => int.tryParse(codigo.split('-').last);

/// Dibuja el sticker completo en un espacio de 384 x 378, en blanco y negro.
void pintarEtiqueta(Canvas canvas, DatosEtiqueta d) {
  final negro = Paint()..color = _negro;
  canvas.drawRect(const Rect.fromLTWH(0, 0, anchoEtiqueta, altoEtiqueta), Paint()..color = _blanco);

  // Banda negra con el logo en blanco y la fecha y hora de compra.
  canvas.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(6, 6, 372, 52), const Radius.circular(10)),
    negro,
  );
  canvas.save();
  canvas.translate(16, 18);
  const CatalogMarkPainter(cuerpo: _blanco, tubos: _blanco).paint(canvas, const Size(54, 27.2));
  canvas.restore();
  _texto(canvas, 'CataLog', x: 78, y: 14, tamano: 27, ancho: 140, familia: fuenteUi, peso: FontWeight.w700, color: _blanco);
  _texto(canvas, fechaCorta(d.fechaCompra),
      x: 200, y: 10, tamano: 19, ancho: 168, familia: fuenteMono, alinear: TextAlign.right, color: _blanco);
  _texto(canvas, hora(d.fechaCompra),
      x: 200, y: 32, tamano: 19, ancho: 168, familia: fuenteMono, alinear: TextAlign.right, color: _blanco);

  // Código grande.
  _texto(canvas, d.codigo,
      x: 0, y: 64, tamano: 32, ancho: anchoEtiqueta, familia: fuenteMono,
      peso: FontWeight.w500, alinear: TextAlign.center);
  canvas.drawRect(const Rect.fromLTWH(10, 108, 364, 2), negro);

  // QR (con guiones) y datos a su derecha.
  _qr(canvas, d.codigo, const Rect.fromLTWH(8, 116, 156, 156));
  _texto(canvas, 'C O M P R A D O', x: 174, y: 120, tamano: 13, ancho: 202, familia: fuenteUi, peso: FontWeight.w700);
  _texto(canvas, fechaCorta(d.fechaCompra), x: 174, y: 138, tamano: 26, ancho: 202, familia: fuenteMono, peso: FontWeight.w500);
  _texto(canvas, hora(d.fechaCompra), x: 174, y: 168, tamano: 26, ancho: 202, familia: fuenteMono, peso: FontWeight.w500);
  _texto(canvas, d.tipo, x: 174, y: 204, tamano: 18, ancho: 202, familia: fuenteUi, maxLineas: 2);
  final pieza = _piezaDelDia(d.codigo);
  if (pieza != null && pieza > 0) {
    _texto(canvas, 'Pieza N° $pieza del día', x: 174, y: 248, tamano: 17, ancho: 202, familia: fuenteMono, peso: FontWeight.w500);
  }

  // Code 128 (sin guiones, para que quepa con barras de 2 puntos).
  _code128(canvas, codigoParaBarras(d.codigo), arriba: 282, alto: 60);

  // Pie: hecho con CataLog.
  canvas.drawRect(const Rect.fromLTWH(60, 350, 264, 1.5), negro);
  canvas.save();
  canvas.translate(118, 357);
  const CatalogMarkPainter(cuerpo: _negro, tubos: _negro).paint(canvas, const Size(28, 14.1));
  canvas.restore();
  _texto(canvas, 'Hecho con CataLog', x: 150, y: 354, tamano: 15, ancho: 180, familia: fuenteUi, peso: FontWeight.w700);
}

void _texto(
  Canvas canvas,
  String texto, {
  required double x,
  required double y,
  required double tamano,
  required double ancho,
  required String familia,
  FontWeight peso = FontWeight.w400,
  TextAlign alinear = TextAlign.left,
  int maxLineas = 1,
  Color color = _negro,
}) {
  final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: alinear,
    maxLines: maxLineas,
    ellipsis: '…',
    fontFamily: familia,
    fontSize: tamano,
    fontWeight: peso,
  ))
    ..pushStyle(ui.TextStyle(color: color, fontFamily: familia, fontSize: tamano, fontWeight: peso))
    ..addText(texto);
  final parrafo = pb.build()..layout(ui.ParagraphConstraints(width: ancho));
  canvas.drawParagraph(parrafo, Offset(x, y));
}

void _qr(Canvas canvas, String datos, Rect zona) {
  final img = QrImage(QrCode(
    payload: QrPayload.fromString(datos),
    errorCorrectLevel: QrErrorCorrectLevel.quartile,
  ));
  const margen = 2;
  final n = img.moduleCount + margen * 2;
  final m = (zona.width / n).floorToDouble(); // módulos enteros = impresión nítida
  final lado = m * n;
  final x0 = zona.left + (zona.width - lado) / 2 + margen * m;
  final y0 = zona.top + (zona.height - lado) / 2 + margen * m;
  final negro = Paint()..color = _negro;
  for (var f = 0; f < img.moduleCount; f++) {
    for (var c = 0; c < img.moduleCount; c++) {
      if (img.isDark(f, c)) canvas.drawRect(Rect.fromLTWH(x0 + c * m, y0 + f * m, m, m), negro);
    }
  }
}

void _code128(Canvas canvas, String datos, {required double arriba, required double alto}) {
  final modulos = modulosCode128(datos);
  final total = modulos.length + margenCode128 * 2;
  final ancho = ((anchoEtiqueta - 20) / total).floorToDouble().clamp(1, 4).toDouble();
  final x0 = (anchoEtiqueta - total * ancho) / 2 + margenCode128 * ancho;
  final negro = Paint()..color = _negro;
  var i = 0;
  while (i < modulos.length) {
    if (!modulos[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j < modulos.length && modulos[j]) {
      j++;
    }
    canvas.drawRect(Rect.fromLTWH(x0 + i * ancho, arriba, (j - i) * ancho, alto), negro);
    i = j;
  }
}

/// Dibuja el sticker como imagen del ancho de la impresora.
Future<ui.Image> renderizarEtiqueta(DatosEtiqueta d, {int anchoPx = 384}) {
  final escala = anchoPx / anchoEtiqueta;
  final alto = (altoEtiqueta * escala).round();
  final grabadora = ui.PictureRecorder();
  final canvas = Canvas(grabadora, Rect.fromLTWH(0, 0, anchoPx.toDouble(), alto.toDouble()));
  canvas.scale(escala);
  pintarEtiqueta(canvas, d);
  return grabadora.endRecording().toImage(anchoPx, alto);
}

/// Vista previa del sticker en pantalla (es exactamente lo que se imprime).
class EtiquetaVista extends StatelessWidget {
  const EtiquetaVista({super.key, required this.datos});

  final DatosEtiqueta datos;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: CatalogColors.borde),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(6),
      child: AspectRatio(
        aspectRatio: anchoEtiqueta / altoEtiqueta,
        child: CustomPaint(painter: _EtiquetaPainter(datos)),
      ),
    );
  }
}

class _EtiquetaPainter extends CustomPainter {
  _EtiquetaPainter(this.datos);

  final DatosEtiqueta datos;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / anchoEtiqueta);
    pintarEtiqueta(canvas, datos);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EtiquetaPainter old) =>
      old.datos.codigo != datos.codigo ||
      old.datos.fechaCompra != datos.fechaCompra ||
      old.datos.tipo != datos.tipo;
}
