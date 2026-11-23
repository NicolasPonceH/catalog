import 'package:material_ui/material_ui.dart';
import 'package:path_drawing/path_drawing.dart';

import '../theme.dart';

/// Símbolo de CataLog (logo refinado): catalítico de cuerpo facetado con su
/// código de barras calado y los tubos con brida. Se dibuja con las mismas
/// formas del SVG (marca/catalog-icono.svg) para usarlo igual en pantalla y en
/// el sticker.
class CatalogMarkPainter extends CustomPainter {
  const CatalogMarkPainter({
    this.cuerpo = CatalogColors.marino,
    this.tubos = CatalogColors.naranja,
  });

  /// Color del cuerpo. Las barras quedan como huecos y muestran el fondo.
  final Color cuerpo;
  final Color tubos;

  static final Path _tubos = parseSvgPathData(
    'M7.2 27.3h2.6l1.1 1.4h10v6.6h-10l-1.1 1.4H7.2A1.2 1.2 0 0 1 6 35.5v-7a1.2 1.2 0 0 1 1.2-1.2Z'
    'M45 28.6h11.6a1.4 1.4 0 0 1 1.4 1.4v4a1.4 1.4 0 0 1-1.4 1.4H45Z',
  )..fillType = PathFillType.evenOdd;

  static final Path _cuerpo = parseSvgPathData(
    'M15 29.1a2.3 2.3 0 0 1 .7-1.7l8.8-7.9a2.3 2.3 0 0 1 1.6-.6h14.5a2.3 2.3 0 0 1 1.8.8l6.1 7.3'
    'a2.3 2.3 0 0 1 .5 1.5v7a2.3 2.3 0 0 1-.5 1.5l-6.1 7.3a2.3 2.3 0 0 1-1.8.8H26.1a2.3 2.3 0 0 1-1.6-.6'
    'l-8.8-7.9a2.3 2.3 0 0 1-.7-1.7Z'
    'M22.6 25.4h2.7v13.2h-2.7Zm4.5 0h1.7v13.2h-1.7Zm3.5 0h3.2v13.2h-3.2Zm5 0h1.9v13.2h-1.9Zm3.7 0h2.7v13.2h-2.7Z',
  )..fillType = PathFillType.evenOdd;

  // Caja que ocupa el símbolo dentro del lienzo de 64 x 64.
  static const _vx = 6.0, _vy = 18.9, _vw = 52.0, _vh = 26.2;

  /// Proporción ancho/alto del símbolo.
  static const proporcion = _vw / _vh;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width / _vw) < (size.height / _vh) ? size.width / _vw : size.height / _vh;
    canvas.save();
    canvas.translate((size.width - _vw * s) / 2, (size.height - _vh * s) / 2);
    canvas.scale(s);
    canvas.translate(-_vx, -_vy);
    canvas.drawPath(_tubos, Paint()..color = tubos);
    canvas.drawPath(_cuerpo, Paint()..color = cuerpo);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatalogMarkPainter old) => old.cuerpo != cuerpo || old.tubos != tubos;
}

/// Logo horizontal: símbolo + "Cata" + "Log".
class CatalogLogo extends StatelessWidget {
  const CatalogLogo({super.key, this.altura = 28, this.oscuro = false});

  final double altura;

  /// True sobre fondo oscuro (cuerpo y "Cata" en blanco niebla).
  final bool oscuro;

  @override
  Widget build(BuildContext context) {
    final principal = oscuro ? CatalogColors.niebla : CatalogColors.marino;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: Size(altura * CatalogMarkPainter.proporcion * 0.66, altura * 0.66),
          painter: CatalogMarkPainter(cuerpo: principal),
        ),
        SizedBox(width: altura * 0.26),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Cata', style: TextStyle(color: principal)),
              const TextSpan(text: 'Log', style: TextStyle(color: CatalogColors.naranja)),
            ],
          ),
          style: TextStyle(
            fontFamily: fuenteUi,
            fontWeight: FontWeight.w700,
            fontSize: altura * 0.82,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
      ],
    );
  }
}
