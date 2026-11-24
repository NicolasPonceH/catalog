import 'dart:async';
import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'backup/auto.dart';
import 'backup/respaldo.dart';
import 'data/base.dart';
import 'data/compras_repo.dart';
import 'data/dispositivo.dart';
import 'data/fotos.dart';
import 'data/sesiones.dart';
import 'features/bienvenida.dart';
import 'features/inicio_screen.dart';
import 'features/presentacion_screen.dart';
import 'features/principal_screen.dart';
import 'features/traspaso.dart';
import 'i18n.dart';
import 'system/notificaciones.dart';
import 'system/sistema.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');
  final sesiones = await Sesiones.abrir();
  final dispositivo = await AjustesDispositivo.abrir(sesiones.documentos);
  final sesion = sesiones.principal;
  final base = await CatalogDb.abrir(ruta: sesion.rutaBase);
  await dispositivo.migrarDesde(ComprasRepo(base));
  runApp(CatalogRoot(sesiones: sesiones, dispositivo: dispositivo, sesion: sesion, base: base));
}

/// Raíz de la app: guarda la sesión y la base abiertas, cambia de sesión,
/// recibe archivos de otras apps, hace el respaldo automático y bloquea la app.
class CatalogRoot extends StatefulWidget {
  const CatalogRoot({
    super.key,
    required this.sesiones,
    required this.dispositivo,
    required this.sesion,
    required this.base,
  });

  final Sesiones sesiones;
  final AjustesDispositivo dispositivo;
  final Sesion sesion;
  final CatalogDb base;

  @override
  State<CatalogRoot> createState() => _CatalogRootState();
}

class _CatalogRootState extends State<CatalogRoot> with WidgetsBindingObserver implements AccionesApp {
  late Sesion _sesion = widget.sesion;
  late CatalogDb _base = widget.base;
  GlobalKey<ScaffoldMessengerState> _mensajes = GlobalKey();
  GlobalKey<NavigatorState> _navegador = GlobalKey();
  late bool _bloqueada = widget.dispositivo.activado(AjustesDispositivo.bloqueo);

  /// Pantalla de bienvenida animada: se muestra al abrir la app.
  bool _bienvenida = true;
  bool _presentando = false;
  DateTime? _enSegundoPlanDesde;
  List<int>? _archivoPendiente;
  StreamSubscription<void>? _subCambios;

  /// Tiempo fuera de la app después del cual se vuelve a pedir huella o PIN.
  static const _tiempoBloqueo = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _alVolver());
    widget.dispositivo.addListener(_ajustesCambiaron);
    _escucharBase();
  }

  @override
  void dispose() {
    _subCambios?.cancel();
    widget.dispositivo.removeListener(_ajustesCambiaron);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _escucharBase() {
    _subCambios?.cancel();
    _subCambios = _base.cambios.listen((_) => _sincronizarRecordatorio());
    _sincronizarRecordatorio();
  }

  Future<void> _sincronizarRecordatorio() async {
    if (_sesion.esRevision) return;
    try {
      await Notificaciones.sincronizarRecordatorioDiario(base: _base, dispositivo: widget.dispositivo);
    } catch (_) {}
  }

  // ---------- Apariencia ----------

  Paleta? _paletaUsada;
  String? _idiomaUsado;

  void _ajustesCambiaron() {
    if (mounted) setState(() {});
    _sincronizarRecordatorio();
  }

  // El tema "auto" sigue al modo oscuro del teléfono.
  @override
  void didChangePlatformBrightness() => _ajustesCambiaron();

  Paleta _paleta() {
    final d = widget.dispositivo;
    final oscuro = switch (d.temaElegido) {
      'oscuro' => true,
      'auto' => WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark,
      _ => false,
    };
    return Paleta.de(oscuro: oscuro, contraste: d.activado(AjustesDispositivo.contraste));
  }

  /// Los colores que dependen del tema se leen al construir cada widget: al
  /// cambiar de tema se vuelve a construir todo (sin perder la pantalla abierta).
  void _reconstruirTodo() {
    void marcar(Element e) {
      e.markNeedsBuild();
      e.visitChildren(marcar);
    }

    if (mounted) (context as Element).visitChildren(marcar);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final primeraVezEnFondo = _enSegundoPlanDesde == null;
      _enSegundoPlanDesde ??= DateTime.now();
      if (primeraVezEnFondo && !_sesion.esRevision && !_bienvenida) {
        unawaited(Notificaciones.avisarAlSalirDeApp(base: _base, dispositivo: widget.dispositivo));
        unawaited(_sincronizarRecordatorio());
      }
    } else if (state == AppLifecycleState.resumed) {
      final desde = _enSegundoPlanDesde;
      _enSegundoPlanDesde = null;
      if (widget.dispositivo.activado(AjustesDispositivo.bloqueo) &&
          desde != null &&
          DateTime.now().difference(desde) > _tiempoBloqueo) {
        setState(() => _bloqueada = true);
      }
      _alVolver();
    }
  }

  Future<void> _alVolver() async {
    // Archivo de CataLog abierto desde WhatsApp, correo, etc.
    final ruta = await Sistema.archivoRecibido();
    if (ruta != null) {
      try {
        final archivo = File(ruta);
        _archivoPendiente = await archivo.readAsBytes();
        await archivo.delete();
      } catch (_) {}
    }
    _procesarArchivoPendiente();

    // Copia diaria automática en Descargas (solo de las compras propias).
    if (!_sesion.esRevision) {
      try {
        await respaldoAutomatico(base: _base, carpeta: _sesion.carpeta, dispositivo: widget.dispositivo);
      } catch (_) {}
      await _sincronizarRecordatorio();
    }
  }

  void _procesarArchivoPendiente() {
    final bytes = _archivoPendiente;
    if (bytes == null || _bloqueada || _bienvenida) return;
    _archivoPendiente = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _navegador.currentContext;
      if (contexto != null) recibirDatos(contexto, bytes);
    });
  }

  /// Se pasó la bienvenida (y la huella, si estaba bloqueada).
  void _entrar() {
    setState(() {
      _bienvenida = false;
      _bloqueada = false;
    });
    unawaited(Sistema.pedirPermisoNotificaciones());
    _procesarArchivoPendiente();
    _quizasPresentacion();
  }

  /// La primera vez: presentación en carrusel y, si se pide, la guía del Inicio.
  Future<void> _quizasPresentacion() async {
    if (_presentando || widget.dispositivo.activado(AjustesDispositivo.presentacionVista)) return;
    _presentando = true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final navegador = _navegador.currentState;
    if (navegador == null || !mounted) {
      _presentando = false;
      return;
    }
    final verGuia = await abrirPresentacion(navegador);
    await widget.dispositivo.guardar(AjustesDispositivo.presentacionVista, '1');
    _presentando = false;
    if (verGuia) pedirGuiaInicio.value++;
  }

  /// Cierra la base abierta, prepara la nueva sesión y la abre. La app vuelve
  /// al Inicio con los datos de esa sesión.
  Future<void> _cambiar(Future<Sesion> Function() preparar, {String? mensaje}) async {
    await _base.cerrar();
    Object? error;
    var nueva = _sesion;
    try {
      nueva = await preparar();
    } catch (e) {
      error = e;
    }
    CatalogDb base;
    try {
      base = await CatalogDb.abrir(ruta: nueva.rutaBase);
    } catch (e) {
      error ??= e;
      nueva = widget.sesiones.principal;
      base = await CatalogDb.abrir(ruta: nueva.rutaBase);
    }
    await widget.dispositivo.guardar(AjustesDispositivo.sesionActiva, nueva.id);
    if (!nueva.esRevision) await widget.dispositivo.migrarDesde(ComprasRepo(base));
    if (!mounted) return;
    setState(() {
      _sesion = nueva;
      _base = base;
      _mensajes = GlobalKey();
      _navegador = GlobalKey();
    });
    _escucharBase();
    final texto = error == null ? mensaje : '${tr('No se pudo completar', 'Could not complete')}: $error';
    if (texto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mensajes.currentState?.showSnackBar(SnackBar(content: Text(texto)));
      });
    }
  }

  @override
  Future<void> abrirSesion(Sesion sesion, {String? mensaje}) => _cambiar(
        () async => sesion,
        mensaje: mensaje ??
            (sesion.esRevision
                ? '${tr('Sesión de revisión', 'Review session')}: ${sesion.nombre}'
                : tr('Volviste a tus compras', 'Back to your purchases')),
      );

  @override
  Future<void> recibirRevision(ContenidoRespaldo contenido) => _cambiar(
        () => widget.sesiones.guardarRevision(contenido),
        mensaje: tr(
          'Datos recibidos: ${contenido.compras} compras en una sesión de revisión',
          'Data received: ${contenido.compras} purchases in a review session',
        ),
      );

  @override
  Future<void> eliminarRevision(Sesion sesion) async {
    if (_sesion.id == sesion.id) {
      await _cambiar(() async {
        await widget.sesiones.eliminar(sesion);
        return widget.sesiones.principal;
      }, mensaje: tr('Revisión borrada', 'Review deleted'));
    } else {
      await widget.sesiones.eliminar(sesion);
    }
  }

  @override
  Future<void> reemplazarDatos(Future<void> Function(String rutaBase) escribir, {String? mensaje}) =>
      _cambiar(() async {
        await escribir(_sesion.rutaBase);
        return _sesion;
      }, mensaje: mensaje);

  @override
  Widget build(BuildContext context) {
    final paleta = _paleta();
    final d = widget.dispositivo;
    final idioma = d.idiomaElegido;
    final cambioTema = _paletaUsada != null && !identical(paleta, _paletaUsada);
    final cambioIdioma = _idiomaUsado != null && _idiomaUsado != idioma;
    if (cambioTema || cambioIdioma) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconstruirTodo());
    }
    _paletaUsada = paleta;
    _idiomaUsado = idioma;
    CatalogColors.paleta = paleta;
    Idioma.actual = idioma;
    return AppScope(
      base: _base,
      fotos: FotosStore(_sesion.carpeta),
      sesion: _sesion,
      sesiones: widget.sesiones,
      dispositivo: widget.dispositivo,
      acciones: this,
      // Con otra base, toda la app se arma de nuevo desde el Inicio.
      child: CatalogApp(
        key: ObjectKey(_base),
        mensajes: _mensajes,
        navegador: _navegador,
        bienvenida: _bienvenida,
        bloqueada: _bloqueada,
        alEntrar: _entrar,
        paleta: paleta,
        idioma: idioma,
        escalaLetra: d.escalaLetra,
        sinAnimaciones: d.activado(AjustesDispositivo.sinAnimaciones),
      ),
    );
  }
}

/// Ancho máximo de la app en pantallas grandes.
const anchoMaximoApp = 760.0;

class CatalogApp extends StatelessWidget {
  const CatalogApp({
    super.key,
    this.mensajes,
    this.navegador,
    this.bienvenida = false,
    this.bloqueada = false,
    this.alEntrar,
    this.paleta = Paleta.clara,
    this.idioma = 'es',
    this.escalaLetra = 1.0,
    this.sinAnimaciones = false,
  });

  final GlobalKey<ScaffoldMessengerState>? mensajes;
  final GlobalKey<NavigatorState>? navegador;

  /// Colores del tema elegido en Ajustes.
  final Paleta paleta;

  /// Idioma elegido en Ajustes ('es' o 'en').
  final String idioma;

  /// Tamaño de letra elegido en Ajustes (se multiplica por el del teléfono).
  final double escalaLetra;
  final bool sinAnimaciones;

  /// Muestra la bienvenida animada encima de todo.
  final bool bienvenida;

  /// La bienvenida pide huella o PIN para entrar.
  final bool bloqueada;
  final VoidCallback? alEntrar;

  @override
  Widget build(BuildContext context) {
    Idioma.actual = idioma;
    return MaterialApp(
      title: 'CataLog',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: mensajes,
      navigatorKey: navegador,
      theme: catalogTheme(paleta),
      locale: idioma == 'en' ? const Locale('en', 'US') : const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es'), Locale('en', 'US'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Respeta el tamaño de letra del teléfono (más el elegido en Ajustes), con
        // un tope para que nada se desarme.
        final mq = MediaQuery.of(context);
        final base = mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3).scale(100) / 100;
        final contenido = child ?? const SizedBox();
        // En pantallas anchas (tablet o teléfono de lado) la app se centra con un ancho cómodo.
        final app = LayoutBuilder(
          builder: (context, c) => c.maxWidth > anchoMaximoApp
              ? ColoredBox(
                  color: CatalogColors.barra,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: anchoMaximoApp),
                      child: ClipRect(child: contenido),
                    ),
                  ),
                )
              : contenido,
        );
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear((base * escalaLetra).clamp(0.9, 1.45)),
            disableAnimations: mq.disableAnimations || sinAnimaciones,
          ),
          child: Stack(
            children: [
              app,
              if (bienvenida || bloqueada)
                Positioned.fill(
                  child: Bienvenida(
                    key: ValueKey(bloqueada),
                    bloqueada: bloqueada,
                    alEntrar: alEntrar ?? () {},
                  ),
                ),
            ],
          ),
        );
      },
      home: const PrincipalScreen(),
    );
  }
}
