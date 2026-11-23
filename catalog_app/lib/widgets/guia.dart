import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/dispositivo.dart';
import '../theme.dart';

/// Un paso de la guía: qué parte de la pantalla se ilumina y qué se explica.
class PasoGuia {
  const PasoGuia({
    required this.clave,
    required this.titulo,
    required this.texto,
    this.icono = Icons.lightbulb_outline,
  });

  /// Clave del widget que se ilumina.
  final GlobalKey clave;
  final String titulo;
  final String texto;
  final IconData icono;
}

/// Muestra la guía paso a paso encima de la pantalla actual: oscurece todo,
/// ilumina una parte a la vez y explica para qué sirve.
/// Si un paso está más abajo en la pantalla, la guía desplaza la lista hasta él
/// (la lista debe construir todos sus hijos: usar un cacheExtent amplio).
/// Los pasos que no existen (por ejemplo, en una lista vacía) se saltan.
Future<void> mostrarGuia(BuildContext context, List<PasoGuia> pasos) async {
  if (!pasos.any((p) => p.clave.currentContext != null)) return;
  final dispositivo = AppScope.maybeOf(context)?.dispositivo;
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _GuiaEncima(pasos: pasos),
      transitionsBuilder: (_, animacion, _, hijo) => FadeTransition(opacity: animacion, child: hijo),
    ),
  );
  await dispositivo?.guardar(AjustesDispositivo.ayudaUsada, '1');
}

class _GuiaEncima extends StatefulWidget {
  const _GuiaEncima({required this.pasos});

  final List<PasoGuia> pasos;

  @override
  State<_GuiaEncima> createState() => _GuiaEncimaState();
}

class _GuiaEncimaState extends State<_GuiaEncima> with TickerProviderStateMixin {
  final _lienzo = GlobalKey();
  late final _mover = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _pulso = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..repeat();
  int _i = 0;
  Rect? _desde;
  Rect? _hasta;
  bool _moviendo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _irA(0));
  }

  @override
  void dispose() {
    _mover.dispose();
    _pulso.dispose();
    super.dispose();
  }

  Rect? get _actual {
    final hasta = _hasta;
    if (hasta == null) return null;
    final desde = _desde;
    if (desde == null) return hasta;
    return Rect.lerp(desde, hasta, Curves.easeInOutCubic.transform(_mover.value));
  }

  Rect? _medir(PasoGuia paso) {
    final caja = paso.clave.currentContext?.findRenderObject();
    final lienzo = _lienzo.currentContext?.findRenderObject();
    if (caja is! RenderBox || lienzo is! RenderBox || !caja.hasSize || !caja.attached) return null;
    final origen = lienzo.globalToLocal(caja.localToGlobal(Offset.zero));
    final rect = (origen & caja.size).inflate(6);
    // Que el foco no se salga de la pantalla (por ejemplo, una barra de arriba).
    final limite = Offset.zero & lienzo.size;
    return rect.intersect(limite.deflate(2));
  }

  Future<void> _irA(int i) async {
    if (_moviendo || i < 0 || i >= widget.pasos.length) return;
    _moviendo = true;
    final paso = widget.pasos[i];
    // El contexto es de la pantalla de abajo (otra ruta), no de la guía.
    // Las pantallas con guía construyen toda su lista (cacheExtent amplio),
    // así que si no hay contexto es porque ese paso no existe ahí.
    final ctx = paso.clave.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    final rect = _medir(paso);
    _moviendo = false;
    if (rect == null) {
      // Ese paso no está en esta pantalla: se salta en la misma dirección.
      final atras = i < _i;
      final otro = atras ? i - 1 : i + 1;
      if (otro >= 0 && otro < widget.pasos.length) {
        await _irA(otro);
      } else if (!atras || _hasta == null) {
        _cerrar();
      }
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _desde = _actual;
      _hasta = rect;
      _i = i;
    });
    _mover.forward(from: 0);
  }

  void _siguiente() => _i + 1 < widget.pasos.length ? _irA(_i + 1) : _cerrar();

  void _cerrar() {
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final paso = widget.pasos[_i];
    final total = widget.pasos.length;
    final ultimo = _i == total - 1;
    final relleno = MediaQuery.paddingOf(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        key: _lienzo,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _siguiente,
              child: AnimatedBuilder(
                animation: Listenable.merge([_mover, _pulso]),
                builder: (context, _) => CustomPaint(painter: _PintorFoco(_actual, _pulso.value)),
              ),
            ),
          ),
          if (_hasta != null)
            AnimatedBuilder(
              animation: _mover,
              builder: (context, hijo) => CustomSingleChildLayout(
                delegate: _UbicarTarjeta(_actual!, relleno),
                child: hijo,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (hijo, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
                    child: hijo,
                  ),
                ),
                child: _Tarjeta(
                  key: ValueKey(_i),
                  paso: paso,
                  numero: _i + 1,
                  total: total,
                  ultimo: ultimo,
                  alAtras: _i == 0 ? null : () => _irA(_i - 1),
                  alSiguiente: _siguiente,
                  alCerrar: _cerrar,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta con la explicación del paso.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    super.key,
    required this.paso,
    required this.numero,
    required this.total,
    required this.ultimo,
    required this.alAtras,
    required this.alSiguiente,
    required this.alCerrar,
  });

  final PasoGuia paso;
  final int numero;
  final int total;
  final bool ultimo;
  final VoidCallback? alAtras;
  final VoidCallback alSiguiente;

  /// La ✕ va dentro de la tarjeta para no tapar los botones de la barra de arriba.
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CatalogColors.superficie,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: CatalogColors.naranjaClara, shape: BoxShape.circle),
                  child: Icon(paso.icono, color: CatalogColors.naranja, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(paso.titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(paso.texto, style: const TextStyle(fontSize: 14.5, height: 1.38)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    tooltip: 'Salir de la guía',
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    color: CatalogColors.acero,
                    onPressed: alCerrar,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Puntos(actual: numero - 1, total: total),
                const Spacer(),
                if (alAtras != null)
                  TextButton(onPressed: alAtras, child: const Text('Atrás')),
                const SizedBox(width: 4),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: alSiguiente,
                  child: Text(ultimo ? 'Listo' : 'Siguiente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Puntos de avance: el actual es una píldora naranja.
class _Puntos extends StatelessWidget {
  const _Puntos({required this.actual, required this.total});

  final int actual;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total > 8) {
      return Text('${actual + 1} de $total', style: etiqueta);
    }
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(right: 4),
            width: i == actual ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == actual ? CatalogColors.naranja : CatalogColors.borde,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// Pone la tarjeta debajo del foco si cabe; si no, arriba; si no, al medio.
class _UbicarTarjeta extends SingleChildLayoutDelegate {
  _UbicarTarjeta(this.foco, this.relleno);

  final Rect foco;
  final EdgeInsets relleno;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints(maxWidth: math.min(c.maxWidth - 24, 420), maxHeight: c.maxHeight * 0.6);

  @override
  Offset getPositionForChild(Size lienzo, Size hijo) {
    final double x =
        (foco.center.dx - hijo.width / 2).clamp(12.0, math.max(12.0, lienzo.width - hijo.width - 12)).toDouble();
    final abajo = foco.bottom + 16;
    final arriba = foco.top - 16 - hijo.height;
    final double y;
    if (abajo + hijo.height <= lienzo.height - relleno.bottom - 12) {
      y = abajo;
    } else if (arriba >= relleno.top + 56) {
      y = arriba;
    } else {
      y = lienzo.height - relleno.bottom - hijo.height - 16;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_UbicarTarjeta old) => old.foco != foco || old.relleno != relleno;
}

/// Oscurece la pantalla con un hueco en el foco, borde naranja y un pulso.
class _PintorFoco extends CustomPainter {
  _PintorFoco(this.foco, this.pulso);

  final Rect? foco;
  final double pulso;

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Path()..addRect(Offset.zero & size);
    final sombra = Paint()..color = const Color(0xD906121F);
    final f = foco;
    if (f == null) {
      canvas.drawPath(todo, sombra);
      return;
    }
    final hueco = RRect.fromRectAndRadius(f, const Radius.circular(14));
    canvas.drawPath(Path.combine(PathOperation.difference, todo, Path()..addRRect(hueco)), sombra);
    canvas.drawRRect(
      hueco,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = CatalogColors.naranja,
    );
    // Dos ondas que salen del foco, desfasadas.
    for (final desfase in [0.0, 0.5]) {
      final t = (pulso + desfase) % 1.0;
      canvas.drawRRect(
        hueco.inflate(4 + 16 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - t) + 0.5
          ..color = CatalogColors.naranja.withValues(alpha: 0.65 * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_PintorFoco old) => old.foco != foco || old.pulso != pulso;
}

/// El típico botón de ayuda (círculo con signo de pregunta) que abre la guía
/// de la pantalla. Hasta que se usa por primera vez, late con un halo naranja.
class BotonAyuda extends StatefulWidget {
  const BotonAyuda({super.key, required this.alTocar});

  final Future<void> Function() alTocar;

  @override
  State<BotonAyuda> createState() => _BotonAyudaState();
}

class _BotonAyudaState extends State<BotonAyuda> with SingleTickerProviderStateMixin {
  late final _halo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  bool get _destacar {
    final dispositivo = AppScope.maybeOf(context)?.dispositivo;
    return dispositivo != null && !dispositivo.activado(AjustesDispositivo.ayudaUsada);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ajustarHalo();
  }

  void _ajustarHalo() {
    if (_destacar) {
      if (!_halo.isAnimating) _halo.repeat();
    } else {
      _halo.stop();
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  Future<void> _tocar() async {
    _halo.stop();
    await widget.alTocar();
    if (mounted) setState(_ajustarHalo);
  }

  @override
  Widget build(BuildContext context) {
    final destacar = _destacar;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (destacar)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _halo,
              builder: (context, _) {
                final t = _halo.value;
                return Container(
                  width: 30 + 18 * t,
                  height: 30 + 18 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CatalogColors.naranja.withValues(alpha: 0.9 * (1 - t)),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
          ),
        IconButton(
          tooltip: 'Ayuda: guía de esta pantalla',
          icon: const Icon(Icons.help_outline),
          onPressed: _tocar,
        ),
        if (destacar)
          const Positioned(
            right: 9,
            top: 9,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(color: CatalogColors.naranja, shape: BoxShape.circle),
                child: SizedBox(width: 8, height: 8),
              ),
            ),
          ),
      ],
    );
  }
}
