import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../theme.dart';
import 'escanear_screen.dart';
import 'historial_screen.dart';
import 'inicio_screen.dart';
import 'lotes_screen.dart';
import 'reportes_screen.dart';

/// Pestañas de la barra de abajo (Escanear no es pestaña: es el botón del centro).
enum Pestana { inicio, historial, lotes, reportes }

/// Da a las pantallas de las pestañas acceso a la barra: cambiar de pestaña y
/// las claves que ilumina la guía del Inicio.
class BarraPrincipal extends InheritedWidget {
  const BarraPrincipal({
    super.key,
    required this.claveEscanear,
    required this.claveBarra,
    required this.irA,
    required super.child,
  });

  final GlobalKey claveEscanear;
  final GlobalKey claveBarra;
  final void Function(Pestana pestana) irA;

  static BarraPrincipal? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<BarraPrincipal>();

  @override
  bool updateShouldNotify(BarraPrincipal old) => false;
}

/// Pantalla principal: Inicio, Historial, Lotes y Reportes en pestañas, con
/// el botón de Escanear grande al centro de la barra.
class PrincipalScreen extends StatefulWidget {
  const PrincipalScreen({super.key});

  @override
  State<PrincipalScreen> createState() => _PrincipalScreenState();
}

class _PrincipalScreenState extends State<PrincipalScreen> {
  Pestana _actual = Pestana.inicio;
  final _claveEscanear = GlobalKey();
  final _claveBarra = GlobalKey();

  static const _pantallas = [InicioScreen(), HistorialScreen(), LotesScreen(), ReportesScreen()];

  @override
  void initState() {
    super.initState();
    // La guía del Inicio se muestra en el Inicio.
    pedirGuiaInicio.addListener(_alInicio);
  }

  @override
  void dispose() {
    pedirGuiaInicio.removeListener(_alInicio);
    super.dispose();
  }

  void _alInicio() {
    if (mounted && _actual != Pestana.inicio) setState(() => _actual = Pestana.inicio);
  }

  void _irA(Pestana p) {
    if (p == _actual) return;
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _actual = p);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Atrás desde otra pestaña vuelve al Inicio; desde el Inicio sale de la app.
      canPop: _actual == Pestana.inicio,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _irA(Pestana.inicio);
      },
      child: BarraPrincipal(
        claveEscanear: _claveEscanear,
        claveBarra: _claveBarra,
        irA: _irA,
        child: Scaffold(
          backgroundColor: CatalogColors.fondo,
          body: IndexedStack(index: _actual.index, children: _pantallas),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          floatingActionButton: BotonEscanear(
            key: _claveEscanear,
            alTocar: () => abrir(context, const EscanearScreen()),
          ),
          bottomNavigationBar: _Barra(key: _claveBarra, actual: _actual, alElegir: _irA),
        ),
      ),
    );
  }
}

/// Barra azul pegada abajo, con un espacio al centro para el botón de Escanear.
class _Barra extends StatelessWidget {
  const _Barra({super.key, required this.actual, required this.alElegir});

  final Pestana actual;
  final ValueChanged<Pestana> alElegir;

  @override
  Widget build(BuildContext context) {
    Widget item(Pestana p, IconData icono, IconData iconoActivo, String texto) => _Item(
          icono: icono,
          iconoActivo: iconoActivo,
          texto: texto,
          activo: actual == p,
          alTocar: () => alElegir(p),
        );
    return Material(
      color: CatalogColors.barra,
      elevation: 10,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              item(Pestana.inicio, Icons.home_outlined, Icons.home, 'Inicio'),
              item(Pestana.historial, Icons.history, Icons.history, 'Historial'),
              const Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 9),
                    child: Text('Escanear', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                  ),
                ),
              ),
              item(Pestana.lotes, Icons.inventory_2_outlined, Icons.inventory_2, 'Lotes'),
              item(Pestana.reportes, Icons.bar_chart_outlined, Icons.bar_chart, 'Reportes'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icono,
    required this.iconoActivo,
    required this.texto,
    required this.activo,
    required this.alTocar,
  });

  final IconData icono;
  final IconData iconoActivo;
  final String texto;
  final bool activo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final color = activo ? CatalogColors.naranja : Colors.white60;
    return Expanded(
      child: Semantics(
        selected: activo,
        button: true,
        label: texto,
        child: InkResponse(
          onTap: alTocar,
          radius: 34,
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: activo ? 1.15 : 1,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(activo ? iconoActivo : icono, color: color, size: 24),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontFamily: fuenteUi,
                  color: color,
                  fontSize: 11.5,
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(texto, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
              const SizedBox(height: 2),
              // Rayita naranja bajo la pestaña activa.
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                width: activo ? 18 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: CatalogColors.naranja,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón redondo naranja de Escanear, que sobresale de la barra. El borde del
/// color del fondo hace que parezca recortado en la barra.
class BotonEscanear extends StatefulWidget {
  const BotonEscanear({super.key, required this.alTocar});

  final VoidCallback alTocar;

  @override
  State<BotonEscanear> createState() => _BotonEscanearState();
}

class _BotonEscanearState extends State<BotonEscanear> {
  bool _apretado = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Escanear sticker',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _apretado = true),
        onTapCancel: () => setState(() => _apretado = false),
        onTapUp: (_) => setState(() => _apretado = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.alTocar();
        },
        child: AnimatedScale(
          scale: _apretado ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CatalogColors.naranja,
              border: Border.all(color: CatalogColors.fondo, width: 6),
              boxShadow: [
                BoxShadow(color: CatalogColors.naranja.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.qr_code_scanner, color: CatalogColors.marino, size: 30),
          ),
        ),
      ),
    );
  }
}
