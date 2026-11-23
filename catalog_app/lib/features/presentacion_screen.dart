import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
import '../theme.dart';
import '../widgets/animaciones.dart';
import '../widgets/catalog_logo.dart';
import 'bienvenida.dart';

/// Abre la presentación como pantalla completa, con un fundido.
/// Devuelve true si al terminar se pidió la guía rápida del Inicio.
Future<bool> abrirPresentacion(NavigatorState navegador) async {
  final r = await navegador.push<bool>(
    PageRouteBuilder<bool>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => const PresentacionScreen(),
      transitionsBuilder: (_, anim, _, hijo) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: hijo,
        ),
      ),
    ),
  );
  return r ?? false;
}

class _Pagina {
  const _Pagina(this.ilustracion, this.titulo, this.texto, this.color);

  final Ilustracion ilustracion;
  final String titulo;
  final String texto;

  /// Tono del fondo de esta página (el fondo se mezcla al deslizar).
  final Color color;
}

const _paginas = [
  _Pagina(
    Ilustracion.bienvenida,
    'Bienvenido a CataLog',
    'Lleva el control de cada catalítico que compras: a quién, cuándo, dónde y cuánto pagaste.',
    Color(0xFF1B4470),
  ),
  _Pagina(
    Ilustracion.registro,
    'Anota cada compra',
    'La fecha y la hora se llenan solas. Agrega el vendedor, el precio, el tipo y una foto. '
        'El GPS funciona aunque no haya señal.',
    Color(0xFF1D4F6E),
  ),
  _Pagina(
    Ilustracion.sticker,
    'Imprime su sticker',
    'Cada catalítico recibe un código único con QR y código de barras. '
        'Imprímelo en tu impresora Bluetooth y pégalo en la pieza.',
    Color(0xFF2A3F6E),
  ),
  _Pagina(
    Ilustracion.escaneo,
    'Escanea y arma lotes',
    'Apunta la cámara al sticker y ves toda su ficha. En un lote, cada lectura suma lo que pagaste.',
    Color(0xFF173F63),
  ),
  _Pagina(
    Ilustracion.reportes,
    'Reportes en Excel',
    'Mira cuánto gastaste por día, semana o mes, por tipo y por vendedor, y mándalo por WhatsApp.',
    Color(0xFF214A5E),
  ),
  _Pagina(
    Ilustracion.seguridad,
    'Tus datos, seguros',
    'Todo queda en tu teléfono, sin internet. Respaldo diario en Descargas y tu huella para borrar o anular.',
    Color(0xFF26406A),
  ),
];

/// Presentación en carrusel de la primera vez. La última página pide el nombre
/// y el prefijo de los códigos (en la sesión de compra).
class PresentacionScreen extends StatefulWidget {
  const PresentacionScreen({super.key});

  @override
  State<PresentacionScreen> createState() => _PresentacionScreenState();
}

class _PresentacionScreenState extends State<PresentacionScreen> {
  final _control = PageController();
  final _nombre = TextEditingController();
  final _prefijo = TextEditingController(text: prefijoPorDefecto);
  double _pos = 0;
  bool _verGuia = true;
  bool _cargado = false;
  String? _errorPrefijo;

  bool get _soloLectura => AppScope.maybeOf(context)?.soloLectura ?? true;
  int get _total => _paginas.length + (_soloLectura ? 0 : 1);
  int get _actual => _pos.round();
  bool get _enUltima => _actual >= _total - 1;

  @override
  void initState() {
    super.initState();
    _control.addListener(() => setState(() => _pos = _control.page ?? 0));
    _nombre.addListener(() => setState(() {}));
    _prefijo.addListener(() => setState(() => _errorPrefijo = null));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cargado) return;
    _cargado = true;
    _cargar();
  }

  Future<void> _cargar() async {
    final scope = AppScope.maybeOf(context);
    if (scope == null || scope.soloLectura) return;
    try {
      final n = await scope.compras.leerAjuste('nombre');
      final p = await scope.compras.leerAjuste('prefijo');
      if (!mounted) return;
      if (n != null && _nombre.text.isEmpty) _nombre.text = n;
      if (p != null) _prefijo.text = p;
    } catch (_) {}
  }

  @override
  void dispose() {
    _control.dispose();
    _nombre.dispose();
    _prefijo.dispose();
    super.dispose();
  }

  void _siguiente() {
    if (_enUltima) {
      _terminar();
      return;
    }
    HapticFeedback.selectionClick();
    _control.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
  }

  Future<void> _terminar({bool saltar = false}) async {
    final scope = AppScope.maybeOf(context);
    if (!saltar && scope != null && !scope.soloLectura) {
      final error = validarPrefijo(_prefijo.text);
      if (error != null) {
        setState(() => _errorPrefijo = error);
        return;
      }
      await scope.compras.guardarAjuste('prefijo', normalizarPrefijo(_prefijo.text));
      if (_nombre.text.trim().isNotEmpty) await scope.compras.guardarAjuste('nombre', _nombre.text.trim());
    }
    if (mounted) Navigator.of(context).pop(!saltar && _verGuia);
  }

  Color _fondo() {
    final i = _pos.floor().clamp(0, _paginas.length - 1);
    final j = (i + 1).clamp(0, _paginas.length - 1);
    return Color.lerp(_paginas[i].color, _paginas[j].color, (_pos - i).clamp(0.0, 1.0))!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CatalogColors.marino,
      resizeToAvoidBottomInset: true,
      body: FondoAnimado(
        colores: [_fondo(), CatalogColors.marino, azulOscuro],
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                child: Row(
                  children: [
                    const CatalogLogo(altura: 22, oscuro: true),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: _enUltima ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        onPressed: _enUltima ? null : () => _terminar(saltar: true),
                        child: const Text('Saltar'),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _control,
                  itemCount: _total,
                  onPageChanged: (_) => HapticFeedback.selectionClick(),
                  itemBuilder: (context, i) =>
                      i < _paginas.length ? _pagina(_paginas[i], _pos - i) : _paginaFinal(_pos - i),
                ),
              ),
              _puntos(),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _siguiente,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Row(
                        key: ValueKey(_enUltima),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_enUltima ? 'Empezar' : 'Siguiente'),
                          const SizedBox(width: 8),
                          Icon(_enUltima ? Icons.check : Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _puntos() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _total; i++)
          Builder(
            builder: (context) {
              final cerca = (1 - (_pos - i).abs()).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 8 + 18 * cerca,
                height: 8,
                decoration: BoxDecoration(
                  color: Color.lerp(Colors.white24, CatalogColors.naranja, cerca),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _pagina(_Pagina p, double delta) {
    final visible = (1 - delta.abs() * 0.7).clamp(0.0, 1.0);
    return LayoutBuilder(
      // Si no cabe (pantalla chica o letra grande), la página se desplaza.
      builder: (context, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: _contenidoPagina(p, delta, visible, (c.maxHeight * 0.48).clamp(130.0, 300.0)),
        ),
      ),
    );
  }

  Widget _contenidoPagina(_Pagina p, double delta, double visible, double altoIlustracion) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          height: altoIlustracion,
          child: Opacity(
            opacity: visible,
            child: Transform.translate(
              offset: Offset(-90 * delta, 0),
              child: Center(child: IlustracionAnimada(p.ilustracion)),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Transform.translate(
          offset: Offset(-40 * delta, 0),
          child: Text(
            p.titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CatalogColors.niebla,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Opacity(
          opacity: visible,
          child: Text(
            p.texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 16, height: 1.45),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _paginaFinal(double delta) {
    final ini = iniciales(_nombre.text);
    final prefijo = normalizarPrefijo(_prefijo.text.isEmpty ? prefijoPorDefecto : _prefijo.text);
    final hoy = DateTime.now();
    final ejemplo = formatearCodigo(prefijo, hoy, 1);
    const etiquetaCampo = TextStyle(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w500);
    final tarjeta = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    );
    return Opacity(
      opacity: (1 - delta.abs() * 0.7).clamp(0.0, 1.0),
      // Centrada en el alto disponible, como las demás páginas; si no cabe, se desplaza.
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFA25C), CatalogColors.naranja],
                      ),
                      boxShadow: [BoxShadow(color: CatalogColors.naranja.withValues(alpha: 0.35), blurRadius: 24)],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (h, a) => ScaleTransition(scale: a, child: h),
                      child: ini.isEmpty
                          ? const Icon(Icons.person, key: ValueKey('sin'), size: 44, color: CatalogColors.marino)
                          : Text(
                              ini,
                              key: ValueKey(ini),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: CatalogColors.marino,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Antes de empezar',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CatalogColors.niebla, fontSize: 26, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Así CataLog te saluda por tu nombre y tus códigos no se repiten con los del otro comprador.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 24),
                // Etiquetas arriba de cada campo (sobre el fondo azul se leen mejor que flotando en el borde).
                const Text('Tu nombre', style: etiquetaCampo),
                const SizedBox(height: 6),
                TextField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'Ej: Juan Pérez', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 14),
                const Text('Prefijo de los códigos (2 a 5 letras)', style: etiquetaCampo),
                const SizedBox(height: 6),
                TextField(
                  controller: _prefijo,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 5,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]'))],
                  style: mono(size: 16),
                  decoration: InputDecoration(
                    hintText: 'CTL',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    errorText: _errorPrefijo,
                    errorStyle: const TextStyle(color: Color(0xFFFFB4A8)),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: tarjeta,
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code_2, color: CatalogColors.naranja, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Así se verán tus códigos',
                              style: TextStyle(color: Colors.white60, fontSize: 12.5),
                            ),
                            const SizedBox(height: 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                ejemplo,
                                key: ValueKey(ejemplo),
                                style: mono(size: 18, color: CatalogColors.niebla),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Misma tarjeta y mismos bordes que la de arriba, para que todo quede alineado.
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _verGuia = !_verGuia),
                    child: Ink(
                      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                      decoration: tarjeta,
                      child: Row(
                        children: [
                          const Icon(Icons.help_outline, color: CatalogColors.naranja, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Mostrarme una guía rápida al entrar',
                              style: TextStyle(color: CatalogColors.niebla, fontSize: 15),
                            ),
                          ),
                          Switch(
                            value: _verGuia,
                            onChanged: (v) => setState(() => _verGuia = v),
                            activeThumbColor: CatalogColors.marino,
                            activeTrackColor: CatalogColors.naranja,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
