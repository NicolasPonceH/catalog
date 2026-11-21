import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// Símbolo de CataLog: un catalítico (cuerpo con código de barras) con sus
/// tubos. Se dibuja con código para usarlo igual en pantalla y en el sticker.
class CatalogMarkPainter extends CustomPainter {
  const CatalogMarkPainter({
    this.cuerpo = CatalogColors.marino,
    this.tubos = CatalogColors.naranja,
  });

  /// Color del cuerpo. Las barras quedan como huecos y muestran el fondo.
  final Color cuerpo;
  final Color tubos;

  // Geometría en una caja de 64 x 64 (igual que catalog-icono.svg).
  static const _vx = 6.0, _vy = 18.0, _vw = 52.0, _vh = 28.0;
  static const _barras = <(double, double)>[
    (22, 2.2), (25.6, 1.1), (28, 2.6), (32, 1.1), (34.6, 2.2), (38.2, 1.1), (40.5, 1.8),
  ];

  /// Proporción ancho/alto del símbolo.
  static const proporcion = _vw / _vh;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (size.width / _vw) < (size.height / _vh)
        ? size.width / _vw
        : size.height / _vh;
    canvas.save();
    canvas.translate((size.width - _vw * s) / 2, (size.height - _vh * s) / 2);
    canvas.scale(s);
    canvas.translate(-_vx, -_vy);

    final pintaTubos = Paint()..color = tubos;
    const r = Radius.circular(2.5);
    canvas.drawRRect(RRect.fromLTRBR(6, 28.5, 19, 35.5, r), pintaTubos);
    canvas.drawRRect(RRect.fromLTRBR(45, 28.5, 58, 35.5, r), pintaTubos);

    final camino = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromLTRBR(15, 18, 49, 46, const Radius.circular(12)));
    for (final (x, ancho) in _barras) {
      camino.addRect(Rect.fromLTWH(x, 25.5, ancho, 13));
    }
    canvas.drawPath(camino, Paint()..color = cuerpo);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CatalogMarkPainter old) =>
      old.cuerpo != cuerpo || old.tubos != tubos;
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
          size: Size(altura * CatalogMarkPainter.proporcion * 0.62, altura * 0.62),
          painter: CatalogMarkPainter(cuerpo: principal),
        ),
        SizedBox(width: altura * 0.28),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Cata', style: TextStyle(color: principal)),
              const TextSpan(
                text: 'Log',
                style: TextStyle(color: CatalogColors.naranja),
              ),
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
