import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'catalog_logo.dart';

/// Avance de 0 a 1 dentro de un tramo [desde, hasta] de una animación.
double tramo(double t, double desde, double hasta) => ((t - desde) / (hasta - desde)).clamp(0.0, 1.0);

const azulClaro = Color(0xFF1B4470);
const azulOscuro = Color(0xFF081B2F);

// ---------------------------------------------------------------------------
// Símbolo de CataLog que se arma solo
// ---------------------------------------------------------------------------

/// Dibuja el símbolo de CataLog armándose: el cuerpo aparece con rebote, los
/// tubos entran por los lados y las barras del código se abren una a una.
/// Con [escaneo] una línea naranja recorre el cuerpo como un lector.
class PintorMarcaAnimada extends CustomPainter {
  PintorMarcaAnimada({
    required this.armado,
    this.escaneo,
    this.cuerpo = CatalogColors.niebla,
    this.tubos = CatalogColors.naranja,
  });

  final double armado;
  final double? escaneo;
  final Color cuerpo;
  final Color tubos;

  @override
  void paint(Canvas canvas, Size size) {
    const caja = CatalogMarkPainter.caja;
    final s = math.min(size.width / caja.width, size.height / caja.height);
    canvas.save();
    canvas.translate((size.width - caja.width * s) / 2, (size.height - caja.height * s) / 2);
    canvas.scale(s);
    canvas.translate(-caja.left, -caja.top);

    final tTubos = Curves.easeOutCubic.transform(tramo(armado, 0.25, 0.6));
    if (tTubos > 0) {
      final p = Paint()..color = tubos.withValues(alpha: tTubos);
      canvas.save();
      canvas.translate(-12 * (1 - tTubos), 0);
      canvas.drawPath(CatalogMarkPainter.tuboIzquierdo, p);
      canvas.restore();
      canvas.save();
      canvas.translate(12 * (1 - tTubos), 0);
      canvas.drawPath(CatalogMarkPainter.tuboDerecho, p);
      canvas.restore();
    }

    final tCuerpo = tramo(armado, 0, 0.45);
    if (tCuerpo > 0) {
      const centro = Offset(32, 32);
      final escala = 0.55 + 0.45 * Curves.easeOutBack.transform(tCuerpo);
      canvas.save();
      canvas.translate(centro.dx, centro.dy);
      canvas.scale(escala);
      canvas.translate(-centro.dx, -centro.dy);
      final limites = CatalogMarkPainter.contorno.getBounds().inflate(3);
      canvas.saveLayer(limites, Paint()..color = Colors.black.withValues(alpha: tramo(armado, 0, 0.2)));
      canvas.drawPath(CatalogMarkPainter.contorno, Paint()..color = cuerpo);
      final hueco = Paint()..blendMode = BlendMode.dstOut;
      for (var i = 0; i < CatalogMarkPainter.barras.length; i++) {
        final tb = Curves.easeOut.transform(tramo(armado, 0.42 + 0.07 * i, 0.56 + 0.07 * i));
        if (tb <= 0) continue;
        final b = CatalogMarkPainter.barras[i];
        canvas.drawRect(Rect.fromCenter(center: b.center, width: b.width, height: b.height * tb), hueco);
      }
      canvas.restore();

      final e = escaneo;
      if (e != null && armado >= 1) {
        canvas.save();
        canvas.clipPath(CatalogMarkPainter.contorno);
        final x = 15 + 34 * e;
        canvas.drawRect(
          Rect.fromLTRB(x - 6, 18, x + 6, 46),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(x - 6, 0),
              Offset(x + 6, 0),
              [
                CatalogColors.naranja.withValues(alpha: 0),
                CatalogColors.naranja.withValues(alpha: 0.55),
                CatalogColors.naranja.withValues(alpha: 0),
              ],
              [0, 0.5, 1],
            ),
        );
        canvas.drawRect(Rect.fromLTRB(x - 0.45, 18, x + 0.45, 46), Paint()..color = CatalogColors.naranja);
        canvas.restore();
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorMarcaAnimada old) =>
      old.armado != armado || old.escaneo != escaneo || old.cuerpo != cuerpo || old.tubos != tubos;
}

// ---------------------------------------------------------------------------
// Huella que se analiza (pantalla de bloqueo)
// ---------------------------------------------------------------------------

/// Huella dactilar dibujada con crestas: se van encendiendo de adentro hacia
/// afuera según [encendido] (0 a 1) y una línea de lector la recorre según
/// [escaneo]. Se dibuja en un lienzo de 100 x 100, dentro de un círculo.
class PintorHuella extends CustomPainter {
  PintorHuella({
    required this.encendido,
    this.escaneo,
    this.color = CatalogColors.naranja,
  });

  final double encendido;
  final double? escaneo;
  final Color color;

  static const _centro = Offset(50, 54);

  /// Crestas: (radio, ángulo inicial, ángulo final) en grados; algunas cortadas en dos.
  static final List<Path> _crestas = () {
    const datos = [
      [5.0, 200.0, 340.0],
      [10.0, 185.0, 360.0],
      [15.0, 175.0, 262.0], [15.0, 274.0, 372.0],
      [20.0, 165.0, 368.0],
      [25.0, 160.0, 238.0], [25.0, 250.0, 380.0],
      [30.0, 158.0, 300.0], [30.0, 312.0, 384.0],
      [35.0, 166.0, 376.0],
      [40.0, 178.0, 252.0], [40.0, 266.0, 364.0],
    ];
    return [
      for (final d in datos)
        Path()
          ..addArc(
            Rect.fromCircle(center: _centro, radius: d[0]),
            d[1] * math.pi / 180,
            (d[2] - d[1]) * math.pi / 180,
          ),
    ];
  }();

  /// Radio de cada cresta (para encenderlas de adentro hacia afuera).
  static const _radios = [5.0, 10.0, 15.0, 15.0, 20.0, 25.0, 25.0, 30.0, 30.0, 35.0, 40.0, 40.0];

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
    canvas.scale(s);
    for (var i = 0; i < _crestas.length; i++) {
      final umbral = (_radios[i] - 5) / 35; // 0 la de adentro, 1 la de afuera
      final luz = ((encendido - umbral) * 5).clamp(0.0, 1.0);
      canvas.drawPath(
        _crestas[i],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(Colors.white.withValues(alpha: 0.22), color, luz)!,
      );
    }
    final e = escaneo;
    if (e != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: const Offset(50, 50), radius: 47)));
      final y = 10 + 80 * e;
      canvas.drawRect(
        Rect.fromLTRB(0, y - 9, 100, y + 9),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, y - 9), Offset(0, y + 9), [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.35),
            color.withValues(alpha: 0),
          ], [0, 0.5, 1]),
      );
      canvas.drawRect(Rect.fromLTRB(4, y - 0.9, 96, y + 0.9), Paint()..color = color);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PintorHuella old) =>
      old.encendido != encendido || old.escaneo != escaneo || old.color != color;
}

// ---------------------------------------------------------------------------
// Fondo azul con partículas que suben (barras de código, cuadritos y anillos)
// ---------------------------------------------------------------------------

class FondoAnimado extends StatefulWidget {
  const FondoAnimado({super.key, this.child, this.colores = const [azulClaro, CatalogColors.marino, azulOscuro]});

  final Widget? child;
  final List<Color> colores;

  @override
  State<FondoAnimado> createState() => _FondoAnimadoState();
}

class _FondoAnimadoState extends State<FondoAnimado> with SingleTickerProviderStateMixin {
  late final _reloj = AnimationController(vsync: this, duration: const Duration(seconds: 40));
  static final _particulas = _Particula.generar(34);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reloj.stop();
    } else if (!_reloj.isAnimating) {
      _reloj.repeat();
    }
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PintorFondo(_reloj, widget.colores, _particulas),
      child: widget.child ?? const SizedBox.expand(),
    );
  }
}

class _Particula {
  const _Particula(this.x, this.y, this.velocidad, this.tamano, this.tipo, this.naranja, this.alfa, this.fase);

  final double x, y, velocidad, tamano, alfa, fase;
  final int tipo; // 0 barra, 1 cuadrito, 2 anillo
  final bool naranja;

  static List<_Particula> generar(int n) {
    final r = math.Random(7);
    return [
      for (var i = 0; i < n; i++)
        _Particula(
          r.nextDouble(),
          r.nextDouble(),
          0.4 + r.nextDouble() * 0.9,
          3 + r.nextDouble() * 9,
          r.nextInt(3),
          r.nextDouble() < 0.22,
          0.05 + r.nextDouble() * 0.12,
          r.nextDouble() * math.pi * 2,
        ),
    ];
  }
}

class _PintorFondo extends CustomPainter {
  _PintorFondo(this.reloj, this.colores, this.particulas) : super(repaint: reloj);

  final Animation<double> reloj;
  final List<Color> colores;
  final List<_Particula> particulas;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.2, size.height * 0.08),
          math.max(size.width, size.height) * 1.15,
          colores,
          [0, 0.55, 1],
        ),
    );
    final t = reloj.value;
    for (final p in particulas) {
      final alto = size.height + 60;
      final y = ((p.y - t * p.velocidad * 2) % 1.0) * alto - 30;
      final x = p.x * size.width + math.sin(t * math.pi * 2 * p.velocidad * 3 + p.fase) * 10;
      final color = (p.naranja ? CatalogColors.naranja : Colors.white).withValues(alpha: p.alfa);
      switch (p.tipo) {
        case 0:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: p.tamano * 0.35, height: p.tamano * 2.2),
                const Radius.circular(1.5)),
            Paint()..color = color,
          );
        case 1:
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: p.tamano, height: p.tamano),
                const Radius.circular(2)),
            Paint()..color = color,
          );
        default:
          canvas.drawCircle(
            Offset(x, y),
            p.tamano * 0.8,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = color,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_PintorFondo old) => old.colores != colores;
}

// ---------------------------------------------------------------------------
// Ilustraciones animadas de la presentación
// ---------------------------------------------------------------------------

enum Ilustracion { bienvenida, registro, sticker, escaneo, reportes, seguridad }

/// Ilustración que se repite en bucle. Se dibuja en un lienzo de 300 x 220.
class IlustracionAnimada extends StatefulWidget {
  const IlustracionAnimada(this.tipo, {super.key});

  final Ilustracion tipo;

  @override
  State<IlustracionAnimada> createState() => _IlustracionAnimadaState();
}

class _IlustracionAnimadaState extends State<IlustracionAnimada> with SingleTickerProviderStateMixin {
  late final _ciclo = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ciclo.value = 0.8;
    } else if (!_ciclo.isAnimating) {
      _ciclo.repeat();
    }
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 300 / 220,
      child: CustomPaint(painter: _PintorIlustracion(widget.tipo, _ciclo, DateTime.now())),
    );
  }
}

class _PintorIlustracion extends CustomPainter {
  _PintorIlustracion(this.tipo, this.ciclo, this.ahora) : super(repaint: ciclo);

  final Ilustracion tipo;
  final Animation<double> ciclo;
  final DateTime ahora;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 300, size.height / 220);
    canvas.save();
    canvas.translate((size.width - 300 * s) / 2, (size.height - 220 * s) / 2);
    canvas.scale(s);
    final t = ciclo.value;
    switch (tipo) {
      case Ilustracion.bienvenida:
        _bienvenida(canvas, t);
      case Ilustracion.registro:
        _registro(canvas, t);
      case Ilustracion.sticker:
        _sticker(canvas, t);
      case Ilustracion.escaneo:
        _escaneo(canvas, t);
      case Ilustracion.reportes:
        _reportes(canvas, t);
      case Ilustracion.seguridad:
        _seguridad(canvas, t);
    }
    canvas.restore();
  }

  // Ondas detrás del símbolo, que se escanea una y otra vez.
  void _bienvenida(Canvas canvas, double t) {
    const centro = Offset(150, 110);
    for (var i = 0; i < 3; i++) {
      final f = (t + i / 3) % 1.0;
      canvas.drawCircle(
        centro,
        50 + 70 * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = CatalogColors.naranja.withValues(alpha: 0.35 * (1 - f)),
      );
    }
    canvas.drawCircle(centro, 62, Paint()..color = Colors.white.withValues(alpha: 0.06));
    final barrido = 0.5 - 0.5 * math.cos(t * math.pi * 2);
    PintorMarcaAnimada(armado: 1, escaneo: barrido).paint(
      canvas..save()..translate(70, 70),
      const Size(160, 80),
    );
    canvas.restore();
  }

  // Formulario que se llena solo, fecha de hoy y un pin de GPS que cae.
  void _registro(Canvas canvas, double t) {
    final alfa = 1 - tramo(t, 0.92, 1);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 300, 220), Paint()..color = Colors.black.withValues(alpha: alfa));
    final tarjeta = RRect.fromRectAndRadius(const Rect.fromLTWH(36, 14, 160, 192), const Radius.circular(16));
    canvas.drawShadow(Path()..addRRect(tarjeta), Colors.black, 8, false);
    canvas.drawRRect(tarjeta, Paint()..color = Colors.white);

    final fecha = RRect.fromRectAndRadius(const Rect.fromLTWH(48, 26, 136, 44), const Radius.circular(10));
    canvas.drawRRect(
      fecha,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = CatalogColors.naranja,
    );
    _icono(canvas, Icons.event, const Offset(66, 48), 22, CatalogColors.naranja);
    _texto(canvas, 'Fecha de compra', const Offset(82, 32), const TextStyle(fontSize: 8.5, color: CatalogColors.acero));
    final hh = ahora.hour.toString().padLeft(2, '0'), mm = ahora.minute.toString().padLeft(2, '0');
    _texto(canvas, 'Hoy · $hh:$mm', const Offset(82, 44),
        const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: CatalogColors.marino));

    const iconos = [Icons.person_outline, Icons.place_outlined, Icons.payments_outlined, Icons.directions_car_outlined];
    const largos = [0.75, 0.6, 0.45, 0.8];
    for (var i = 0; i < 4; i++) {
      final y = 82.0 + i * 29;
      final campo = RRect.fromRectAndRadius(Rect.fromLTWH(48, y, 136, 22), const Radius.circular(7));
      canvas.drawRRect(campo, Paint()..color = CatalogColors.niebla);
      _icono(canvas, iconos[i], Offset(60, y + 11), 13, CatalogColors.acero);
      final avance = Curves.easeOut.transform(tramo(t, 0.08 + 0.12 * i, 0.28 + 0.12 * i));
      if (avance > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(72, y + 8, 100 * largos[i] * avance, 6), const Radius.circular(3)),
          Paint()..color = i == 2 ? CatalogColors.marino : CatalogColors.acero.withValues(alpha: 0.55),
        );
      }
    }

    // Pin de GPS que cae con rebote.
    final caida = Curves.bounceOut.transform(tramo(t, 0.5, 0.78));
    final yPin = 40 + 92 * caida;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(246, 160), width: 34 * caida + 6, height: 9 * caida + 2),
      Paint()..color = Colors.black.withValues(alpha: 0.25 * caida),
    );
    if (t > 0.48) _icono(canvas, Icons.place, Offset(246, yPin), 50, CatalogColors.naranja);
    if (caida >= 1) {
      _texto(canvas, 'GPS ±6 m', const Offset(222, 172), const TextStyle(fontSize: 11, color: Colors.white70));
    }

    // Visto bueno al final.
    final ok = Curves.easeOutBack.transform(tramo(t, 0.8, 0.9));
    if (ok > 0) {
      canvas.drawCircle(const Offset(196, 20), 15 * ok, Paint()..color = CatalogColors.verde);
      _icono(canvas, Icons.check, const Offset(196, 20), 20 * ok, Colors.white);
    }
    canvas.restore();
  }

  // Impresora que va sacando el sticker.
  void _sticker(Canvas canvas, double t) {
    final caja = RRect.fromRectAndRadius(const Rect.fromLTWH(72, 14, 156, 64), const Radius.circular(18));
    canvas.drawShadow(Path()..addRRect(caja), Colors.black, 6, false);
    canvas.drawRRect(caja, Paint()..color = azulClaro);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(78, 18, 144, 20), const Radius.circular(12)),
      Paint()..color = Colors.white.withValues(alpha: 0.06),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(92, 66, 116, 7), const Radius.circular(3)),
      Paint()..color = azulOscuro,
    );
    final parpadeo = (math.sin(t * math.pi * 8) + 1) / 2;
    canvas.drawCircle(const Offset(206, 34), 4, Paint()..color = CatalogColors.verde.withValues(alpha: 0.4 + 0.6 * parpadeo));
    _icono(canvas, Icons.bluetooth, const Offset(96, 36), 18, Colors.white.withValues(alpha: 0.5 + 0.5 * parpadeo));

    // Papel: sale de la ranura; lo primero impreso sale primero.
    final sale = Curves.easeInOut.transform(tramo(t, 0.08, 0.62));
    final cae = Curves.easeIn.transform(tramo(t, 0.8, 0.98));
    const ancho = 100.0, largo = 128.0;
    final alto = largo * sale;
    final arriba = 70 + 36 * cae;
    if (alto <= 0) return;
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 300, 220), Paint()..color = Colors.black.withValues(alpha: 1 - cae));
    final papel = Rect.fromLTWH(150 - ancho / 2, arriba, ancho, alto);
    canvas.save();
    canvas.clipRect(papel);
    canvas.drawRect(papel, Paint()..color = Colors.white);
    final o = Offset(papel.left, arriba + alto - largo);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + 6, o.dy + 6, ancho - 12, 16), const Radius.circular(4)),
      Paint()..color = Colors.black,
    );
    PintorMarcaAnimada(armado: 1, cuerpo: Colors.white, tubos: Colors.white)
        .paint(canvas..save()..translate(o.dx + 10, o.dy + 8), const Size(22, 12));
    canvas.restore();
    _texto(canvas, 'CataLog', Offset(o.dx + 35, o.dy + 8),
        const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: Colors.white));
    _texto(canvas, 'CTL-${_fechaCodigo()}-0001', Offset(o.dx + 8, o.dy + 26),
        const TextStyle(fontSize: 9.5, fontFamily: fuenteMono, fontWeight: FontWeight.w500, color: Colors.black));
    _qr(canvas, Rect.fromLTWH(o.dx + 8, o.dy + 42, 38, 38));
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(o.dx + 52, o.dy + 46 + i * 10.0, 40 - i * 8.0, 4), Paint()..color = Colors.black);
    }
    _barras(canvas, Rect.fromLTWH(o.dx + 8, o.dy + 88, ancho - 16, 22));
    canvas.restore();
    canvas.restore();
  }

  // Celular leyendo un sticker y el lote sumando.
  void _escaneo(Canvas canvas, double t) {
    final telefono = RRect.fromRectAndRadius(const Rect.fromLTWH(70, 8, 112, 204), const Radius.circular(20));
    canvas.drawShadow(Path()..addRRect(telefono), Colors.black, 8, false);
    canvas.drawRRect(telefono, Paint()..color = azulOscuro);
    canvas.drawRRect(
      telefono,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    const sticker = Rect.fromLTWH(92, 52, 68, 76);
    canvas.drawRRect(RRect.fromRectAndRadius(sticker, const Radius.circular(6)), Paint()..color = Colors.white);
    _qr(canvas, Rect.fromLTWH(sticker.left + 10, sticker.top + 8, 48, 48));
    _barras(canvas, Rect.fromLTWH(sticker.left + 8, sticker.top + 60, 52, 10));
    // Esquinas del visor.
    final visor = sticker.inflate(9);
    final esquina = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    for (final (x, y, dx, dy) in [
      (visor.left, visor.top, 1.0, 1.0),
      (visor.right, visor.top, -1.0, 1.0),
      (visor.left, visor.bottom, 1.0, -1.0),
      (visor.right, visor.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + 12 * dy)
          ..lineTo(x, y)
          ..lineTo(x + 12 * dx, y),
        esquina,
      );
    }
    // Línea del lector, que sube y baja.
    final fase = (t * 2) % 1.0;
    final y = sticker.top + 4 + (sticker.height - 8) * (0.5 - 0.5 * math.cos(fase * math.pi * 2));
    canvas.drawRect(
      Rect.fromLTRB(visor.left + 2, y - 7, visor.right - 2, y + 7),
      Paint()
        ..shader = ui.Gradient.linear(Offset(0, y - 7), Offset(0, y + 7), [
          CatalogColors.naranja.withValues(alpha: 0),
          CatalogColors.naranja.withValues(alpha: 0.45),
          CatalogColors.naranja.withValues(alpha: 0),
        ], [0, 0.5, 1]),
    );
    canvas.drawRect(Rect.fromLTRB(visor.left + 2, y - 1, visor.right - 2, y + 1), Paint()..color = CatalogColors.naranja);

    // Cada lectura: visto bueno y el total del lote sube.
    final lecturas = (t * 4).floor();
    final enLectura = (t * 4) % 1.0;
    final pop = Curves.easeOutBack.transform(tramo(enLectura, 0.55, 0.75)) * (1 - tramo(enLectura, 0.9, 1));
    if (pop > 0) {
      canvas.drawCircle(sticker.center, 20 * pop, Paint()..color = CatalogColors.verde);
      _icono(canvas, Icons.check, sticker.center, 26 * pop, Colors.white);
    }
    const montos = [60000, 145000, 230000, 310000];
    final hechas = lecturas + (enLectura >= 0.6 ? 1 : 0);
    final total = hechas == 0 ? 0 : montos[math.min(hechas, 4) - 1];
    final tarjeta = RRect.fromRectAndRadius(const Rect.fromLTWH(170, 150, 112, 48), const Radius.circular(12));
    canvas.drawShadow(Path()..addRRect(tarjeta), Colors.black, 6, false);
    canvas.drawRRect(tarjeta, Paint()..color = Colors.white);
    _texto(canvas, 'Lote · ${math.min(hechas, 4)} piezas', const Offset(180, 156),
        const TextStyle(fontSize: 9.5, color: CatalogColors.acero));
    _texto(canvas, _clp(total), const Offset(180, 170),
        const TextStyle(fontSize: 15, fontFamily: fuenteMono, fontWeight: FontWeight.w500, color: CatalogColors.naranja));
  }

  // Gráfico que crece, línea de tendencia y el ícono de Excel.
  void _reportes(Canvas canvas, double t) {
    final alfa = 1 - tramo(t, 0.93, 1);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 300, 220), Paint()..color = Colors.black.withValues(alpha: alfa));
    final tarjeta = RRect.fromRectAndRadius(const Rect.fromLTWH(28, 22, 228, 182), const Radius.circular(16));
    canvas.drawShadow(Path()..addRRect(tarjeta), Colors.black, 8, false);
    canvas.drawRRect(tarjeta, Paint()..color = Colors.white);
    _texto(canvas, 'Gastado este mes', const Offset(44, 34), const TextStyle(fontSize: 10, color: CatalogColors.acero));
    final total = (880000 * Curves.easeOut.transform(tramo(t, 0.05, 0.5))).round();
    _texto(canvas, _clp(total), const Offset(44, 48),
        const TextStyle(fontSize: 20, fontFamily: fuenteMono, fontWeight: FontWeight.w500, color: CatalogColors.marino));

    const alturas = [42.0, 70, 54, 92, 66, 104, 80];
    final cimas = <Offset>[];
    for (var i = 0; i < alturas.length; i++) {
      final crece = Curves.easeOutBack.transform(tramo(t, 0.1 + 0.05 * i, 0.42 + 0.05 * i));
      final x = 50.0 + i * 28;
      final alto = alturas[i] * crece;
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, 190 - alto, 16, alto),
            topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        Paint()..color = i == 5 ? CatalogColors.naranja : CatalogColors.marino.withValues(alpha: 0.85),
      );
      cimas.add(Offset(x + 8, 190 - alturas[i] - 8));
    }
    final linea = Path()..moveTo(cimas.first.dx, cimas.first.dy);
    for (final c in cimas.skip(1)) {
      linea.lineTo(c.dx, c.dy);
    }
    final trazo = tramo(t, 0.5, 0.8);
    if (trazo > 0) {
      for (final m in linea.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * trazo),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..color = CatalogColors.naranja,
        );
      }
    }
    // Ícono de Excel que salta.
    final salto = math.sin(t * math.pi * 4).abs() * 6;
    final excel = RRect.fromRectAndRadius(Rect.fromLTWH(232, 6 - salto, 50, 50), const Radius.circular(12));
    canvas.drawShadow(Path()..addRRect(excel), Colors.black, 6, false);
    canvas.drawRRect(excel, Paint()..color = const Color(0xFF1D6F42));
    _texto(canvas, 'X', Offset(248, 15 - salto),
        const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white));
    canvas.restore();
  }

  // Escudo con huella que se dibuja, y la carpeta de respaldo.
  void _seguridad(Canvas canvas, double t) {
    const cx = 120.0, arriba = 22.0, ancho = 128.0, abajo = 200.0;
    final escudo = Path()
      ..moveTo(cx, arriba)
      ..lineTo(cx + ancho / 2, arriba + 22)
      ..lineTo(cx + ancho / 2, 100)
      ..quadraticBezierTo(cx + ancho / 2, abajo - 36, cx, abajo)
      ..quadraticBezierTo(cx - ancho / 2, abajo - 36, cx - ancho / 2, 100)
      ..lineTo(cx - ancho / 2, arriba + 22)
      ..close();
    canvas.drawShadow(escudo, Colors.black, 8, false);
    canvas.drawPath(escudo, Paint()..color = azulClaro);
    canvas.drawPath(
      escudo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    // Huella: arcos concéntricos que se van trazando.
    const centro = Offset(cx, 118);
    for (var i = 0; i < 5; i++) {
      final r = 10.0 + i * 8;
      final inicio = math.pi * (1.05 + 0.04 * i);
      final barrido = math.pi * (0.95 - 0.06 * i) + (i.isEven ? 0.5 : 0.9);
      final arco = Path()..addArc(Rect.fromCircle(center: centro, radius: r), inicio, barrido);
      final avance = tramo(t, 0.05 + 0.08 * i, 0.4 + 0.08 * i);
      if (avance <= 0) continue;
      for (final m in arco.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * avance),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..strokeCap = StrokeCap.round
            ..color = CatalogColors.naranja,
        );
      }
    }
    final ok = Curves.easeOutBack.transform(tramo(t, 0.75, 0.86)) * (1 - tramo(t, 0.95, 1));
    if (ok > 0) {
      canvas.drawCircle(const Offset(cx + 46, 172), 15 * ok, Paint()..color = CatalogColors.verde);
      _icono(canvas, Icons.check, const Offset(cx + 46, 172), 20 * ok, Colors.white);
    }
    // Respaldo: carpeta con flecha que baja.
    final baja = (math.sin(t * math.pi * 4) + 1) / 2 * 8;
    _icono(canvas, Icons.folder_zip_outlined, const Offset(240, 138), 58, Colors.white.withValues(alpha: 0.92));
    _icono(canvas, Icons.south, Offset(240, 78 + baja), 30, CatalogColors.naranja);
    _texto(canvas, 'Respaldo diario', const Offset(200, 172), const TextStyle(fontSize: 11, color: Colors.white70));
  }

  // --- utilidades de dibujo ---

  String _fechaCodigo() =>
      '${(ahora.year % 100).toString().padLeft(2, '0')}${ahora.month.toString().padLeft(2, '0')}'
      '${ahora.day.toString().padLeft(2, '0')}';

  static String _clp(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return '\$$b';
  }

  static void _texto(Canvas canvas, String texto, Offset en, TextStyle estilo) {
    final tp = TextPainter(
      text: TextSpan(text: texto, style: estilo.copyWith(fontFamily: estilo.fontFamily ?? fuenteUi)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, en);
  }

  static void _icono(Canvas canvas, IconData icono, Offset centro, double tamano, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icono.codePoint),
        style: TextStyle(fontFamily: icono.fontFamily, package: icono.fontPackage, fontSize: tamano, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centro - Offset(tp.width / 2, tp.height / 2));
  }

  static final List<List<bool>> _patronQr = () {
    const n = 11;
    final r = math.Random(23);
    final m = List.generate(n, (_) => List.filled(n, false));
    bool esGuia(int x, int y) => (x < 4 && y < 4) || (x > 6 && y < 4) || (x < 4 && y > 6);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        m[y][x] = !esGuia(x, y) && r.nextDouble() < 0.45;
      }
    }
    for (final (gx, gy) in [(0, 0), (8, 0), (0, 8)]) {
      for (var j = 0; j < 3; j++) {
        for (var i = 0; i < 3; i++) {
          m[gy + j][gx + i] = true;
        }
      }
    }
    return m;
  }();

  static void _qr(Canvas canvas, Rect r) {
    final celda = r.width / 11;
    final negro = Paint()..color = Colors.black;
    for (var y = 0; y < 11; y++) {
      for (var x = 0; x < 11; x++) {
        if (_patronQr[y][x]) {
          canvas.drawRect(Rect.fromLTWH(r.left + x * celda, r.top + y * celda, celda + 0.2, celda + 0.2), negro);
        }
      }
    }
    // Centro blanco de las tres guías.
    final blanco = Paint()..color = Colors.white;
    for (final (gx, gy) in [(1, 1), (9, 1), (1, 9)]) {
      canvas.drawRect(Rect.fromLTWH(r.left + gx * celda, r.top + gy * celda, celda, celda), blanco);
    }
  }

  static void _barras(Canvas canvas, Rect r) {
    const anchos = [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 3, 1, 2];
    final total = anchos.fold<int>(0, (a, b) => a + b) * 1.6;
    final u = r.width / total;
    var x = r.left;
    final negro = Paint()..color = Colors.black;
    for (var i = 0; i < anchos.length; i++) {
      final w = anchos[i] * u;
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, r.top, w, r.height), negro);
      x += w + (i.isEven ? u * 0.6 : u * 1.2);
    }
  }

  @override
  bool shouldRepaint(_PintorIlustracion old) => old.tipo != tipo;
}
