import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../system/bloqueo.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/animaciones.dart';

/// Pantalla de entrada: el logo se arma solo, saluda por el nombre y muestra lo
/// gastado en el mes. Si el bloqueo está activo, se entra con la huella o el PIN;
/// si no, entra sola en un par de segundos (o al tocar la pantalla).
class Bienvenida extends StatefulWidget {
  const Bienvenida({super.key, required this.bloqueada, required this.alEntrar});

  /// Pide huella o PIN antes de entrar.
  final bool bloqueada;
  final VoidCallback alEntrar;

  @override
  State<Bienvenida> createState() => _BienvenidaState();
}

/// Saludo según la hora del día.
String saludoPorHora(DateTime ahora) {
  final h = ahora.hour;
  if (h >= 6 && h < 12) return 'Buenos días';
  if (h >= 12 && h < 20) return 'Buenas tardes';
  return 'Buenas noches';
}

/// Iniciales para el avatar: primera letra de las dos primeras palabras.
String iniciales(String nombre) {
  final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  return palabras.take(2).map((p) => p.characters.first.toUpperCase()).join();
}

class _BienvenidaState extends State<Bienvenida> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final _escaneo = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final _espera = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  late final _latido = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  late final _salida = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

  String _nombre = '';
  Resumen? _mes;
  bool _revision = false;
  bool _cargado = false;
  bool _pidiendo = false;
  bool _saliendo = false;

  @override
  void initState() {
    super.initState();
    _escaneo.repeat(reverse: true);
    _latido.repeat();
    _intro.forward().whenComplete(_trasIntro);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cargado) return;
    _cargado = true;
    if (MediaQuery.disableAnimationsOf(context)) _intro.value = 1;
    _cargar();
  }

  Future<void> _cargar() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null) return;
    _revision = scope.soloLectura;
    try {
      final nombre = await scope.compras.leerAjuste('nombre');
      final mes = await scope.compras.resumen(periodoMes(DateTime.now()));
      if (!mounted) return;
      setState(() {
        _nombre = nombre?.trim() ?? '';
        _mes = mes;
      });
    } catch (_) {}
  }

  void _trasIntro() {
    if (!mounted || _saliendo) return;
    if (widget.bloqueada) {
      _pedirHuella();
    } else {
      _espera.forward().whenComplete(_entrar);
    }
  }

  Future<void> _pedirHuella() async {
    if (_pidiendo || _saliendo) return;
    setState(() => _pidiendo = true);
    final ok = await Bloqueo.desbloquear('Entra a CataLog');
    if (!mounted) return;
    setState(() => _pidiendo = false);
    if (ok) _entrar();
  }

  void _entrar() {
    if (!mounted || _saliendo) return;
    _saliendo = true;
    _espera.stop();
    HapticFeedback.lightImpact();
    _salida.forward().whenComplete(() {
      if (mounted) widget.alEntrar();
    });
  }

  void _tocar() => widget.bloqueada ? _pedirHuella() : _entrar();

  @override
  void dispose() {
    _intro.dispose();
    _escaneo.dispose();
    _espera.dispose();
    _latido.dispose();
    _salida.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _salida,
      builder: (context, hijo) {
        final v = Curves.easeIn.transform(_salida.value);
        return IgnorePointer(
          ignoring: _saliendo,
          child: Opacity(
            opacity: 1 - v,
            child: Transform.scale(scale: 1 + 0.08 * v, child: hijo),
          ),
        );
      },
      child: Material(
        color: CatalogColors.marino,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tocar,
          child: FondoAnimado(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  // En pantallas muy chicas (o con letra muy grande) se puede desplazar.
                  child: LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: c.maxHeight),
                        child: IntrinsicHeight(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_intro, _escaneo, _espera, _latido]),
                            builder: (context, _) => _contenido(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _aparecer(double desde, double hasta, Widget hijo, {double sube = 22}) {
    final t = Curves.easeOutCubic.transform(tramo(_intro.value, desde, hasta));
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, sube * (1 - t)), child: hijo),
    );
  }

  Widget _contenido(BuildContext context) {
    final i = _intro.value;
    final bajo = MediaQuery.sizeOf(context).height < 700;
    return Column(
      children: [
        const Spacer(flex: 3),
        // Símbolo que se arma, con un resplandor detrás.
        SizedBox(
          width: 230,
          height: bajo ? 100 : 124,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: tramo(i, 0.2, 0.6),
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      CatalogColors.naranja.withValues(alpha: 0.22 + 0.06 * _escaneo.value),
                      CatalogColors.naranja.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              CustomPaint(
                size: Size(bajo ? 170 : 210, bajo ? 86 : 106),
                painter: PintorMarcaAnimada(
                  armado: tramo(i, 0, 0.5),
                  escaneo: i >= 0.5 ? Curves.easeInOut.transform(_escaneo.value) : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _palabraAnimada(i, bajo ? 38 : 46),
        const SizedBox(height: 6),
        _aparecer(
          0.62,
          0.82,
          Text(
            'Control de compras de catalíticos',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 15),
          ),
          sube: 10,
        ),
        const Spacer(flex: 2),
        _aparecer(0.68, 0.92, _tarjetaSaludo()),
        SizedBox(height: bajo ? 16 : 26),
        _aparecer(0.8, 1, widget.bloqueada ? _botonHuella() : _botonEntrar()),
        const Spacer(),
        Opacity(
          opacity: tramo(i, 0.85, 1) * 0.6,
          child: const Text(
            'Versión $versionApp · Hecho en Arica',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// "CataLog" letra por letra.
  Widget _palabraAnimada(double i, double tamano) {
    const palabra = 'CataLog';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var k = 0; k < palabra.length; k++)
          Builder(builder: (context) {
            final t = Curves.easeOutBack.transform(tramo(i, 0.42 + 0.035 * k, 0.58 + 0.035 * k));
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - t)),
                child: Text(
                  palabra[k],
                  style: TextStyle(
                    fontFamily: fuenteUi,
                    fontWeight: FontWeight.w700,
                    fontSize: tamano,
                    letterSpacing: -0.5,
                    height: 1,
                    color: k < 4 ? CatalogColors.niebla : CatalogColors.naranja,
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _tarjetaSaludo() {
    final ini = iniciales(_nombre);
    final corto = _nombre.isEmpty ? '' : _nombre.split(RegExp(r'\s+')).first;
    final avance = Curves.easeOutCubic.transform(tramo(_intro.value, 0.72, 1));
    final mes = _mes;
    const tenue = TextStyle(color: Colors.white60, fontSize: 12.5);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFA25C), CatalogColors.naranja],
                  ),
                ),
                child: ini.isEmpty
                    ? const Icon(Icons.person, color: CatalogColors.marino, size: 28)
                    : Text(ini,
                        style: const TextStyle(
                            color: CatalogColors.marino, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      corto.isEmpty ? saludoPorHora(DateTime.now()) : '${saludoPorHora(DateTime.now())},',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Text(
                      corto.isEmpty ? 'Bienvenido' : corto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CatalogColors.niebla, fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: CatalogColors.naranja.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_revision ? Icons.fact_check_outlined : Icons.shopping_bag_outlined,
                              size: 14, color: CatalogColors.naranja),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _revision ? 'Sesión de revisión' : 'Mis compras',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: CatalogColors.niebla, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: 24, color: Colors.white.withValues(alpha: 0.1)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_revision ? 'Recibido este mes' : 'Gastado este mes', style: tenue),
                    const SizedBox(height: 2),
                    Text(
                      mes == null ? '—' : clp((mes.total * avance).round()),
                      style: mono(size: 22, color: CatalogColors.naranja),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Catalíticos', style: tenue),
                  const SizedBox(height: 2),
                  Text(
                    mes == null ? '—' : '${(mes.cantidad * avance).round()}',
                    style: mono(size: 22, color: CatalogColors.niebla),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonHuella() {
    final t = _latido.value;
    return Column(
      children: [
        GestureDetector(
          onTap: _pedirHuella,
          child: SizedBox(
            width: 112,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final desfase in [0.0, 0.5])
                  Builder(builder: (context) {
                    final f = (t + desfase) % 1.0;
                    return Container(
                      width: 72 + 40 * f,
                      height: 72 + 40 * f,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: CatalogColors.naranja.withValues(alpha: 0.6 * (1 - f)),
                          width: 2,
                        ),
                      ),
                    );
                  }),
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: CatalogColors.naranja, shape: BoxShape.circle),
                  child: const Icon(Icons.fingerprint, size: 42, color: CatalogColors.marino),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _pidiendo ? 'Esperando tu huella o PIN…' : 'Toca para entrar con tu huella',
          style: const TextStyle(color: CatalogColors.niebla, fontSize: 15),
        ),
      ],
    );
  }

  Widget _botonEntrar() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _entrar,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('Entrar'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 20)],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: _espera.value,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            color: CatalogColors.naranja,
          ),
        ),
      ],
    );
  }
}
