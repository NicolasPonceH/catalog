import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

/// Código QR dibujado con código propio (el mismo se usará para imprimir).
class QrVista extends StatelessWidget {
  const QrVista({super.key, required this.datos, this.tamano = 160});

  final String datos;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final imagen = QrImage(QrCode(
      payload: QrPayload.fromString(datos),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ));
    return CustomPaint(size: Size.square(tamano), painter: _QrPainter(imagen));
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.imagen);

  final QrImage imagen;
  static const _margen = 2; // módulos blancos alrededor

  @override
  void paint(Canvas canvas, Size size) {
    final n = imagen.moduleCount + _margen * 2;
    final m = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final negro = Paint()..color = const Color(0xFF000000);
    for (var f = 0; f < imagen.moduleCount; f++) {
      for (var c = 0; c < imagen.moduleCount; c++) {
        if (imagen.isDark(f, c)) {
          canvas.drawRect(
            Rect.fromLTWH((c + _margen) * m, (f + _margen) * m, m + 0.5, m + 0.5),
            negro,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => false;
}
