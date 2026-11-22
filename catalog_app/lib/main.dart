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
import 'features/inicio_screen.dart';
import 'features/traspaso.dart';
import 'system/bloqueo.dart';
import 'system/sistema.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final sesiones = await Sesiones.abrir();
  final dispositivo = await AjustesDispositivo.abrir(sesiones.documentos);
  var sesion = await sesiones.buscar(dispositivo.leer(AjustesDispositivo.sesionActiva)) ?? sesiones.principal;
  CatalogDb base;
  try {
    base = await CatalogDb.abrir(ruta: sesion.rutaBase);
  } catch (_) {
    sesion = sesiones.principal;
    base = await CatalogDb.abrir(ruta: sesion.rutaBase);
  }
  if (!sesion.esRevision) await dispositivo.migrarDesde(ComprasRepo(base));
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
  DateTime? _enSegundoPlanDesde;
  List<int>? _archivoPendiente;

  /// Tiempo fuera de la app después del cual se vuelve a pedir huella o PIN.
  static const _tiempoBloqueo = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _alVolver());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _enSegundoPlanDesde ??= DateTime.now();
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
    }
  }

  void _procesarArchivoPendiente() {
    final bytes = _archivoPendiente;
    if (bytes == null || _bloqueada) return;
    _archivoPendiente = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contexto = _navegador.currentContext;
      if (contexto != null) recibirDatos(contexto, bytes);
    });
  }

  void _desbloquear() {
    setState(() => _bloqueada = false);
    _procesarArchivoPendiente();
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
    final texto = error == null ? mensaje : 'No se pudo completar: $error';
    if (texto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mensajes.currentState?.showSnackBar(SnackBar(content: Text(texto)));
      });
    }
  }

  @override
  Future<void> abrirSesion(Sesion sesion, {String? mensaje}) => _cambiar(
        () async => sesion,
        mensaje: mensaje ?? (sesion.esRevision ? 'Sesión de revisión: ${sesion.nombre}' : 'Volviste a tus compras'),
      );

  @override
  Future<void> recibirRevision(ContenidoRespaldo contenido) => _cambiar(
        () => widget.sesiones.guardarRevision(contenido),
        mensaje: 'Datos recibidos: ${contenido.compras} compras en una sesión de revisión',
      );

  @override
  Future<void> eliminarRevision(Sesion sesion) async {
    if (_sesion.id == sesion.id) {
      await _cambiar(() async {
        await widget.sesiones.eliminar(sesion);
        return widget.sesiones.principal;
      }, mensaje: 'Revisión borrada');
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
        bloqueada: _bloqueada,
        alDesbloquear: _desbloquear,
      ),
    );
  }
}

class CatalogApp extends StatelessWidget {
  const CatalogApp({
    super.key,
    this.mensajes,
    this.navegador,
    this.bloqueada = false,
    this.alDesbloquear,
  });

  final GlobalKey<ScaffoldMessengerState>? mensajes;
  final GlobalKey<NavigatorState>? navegador;
  final bool bloqueada;
  final VoidCallback? alDesbloquear;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CataLog',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: mensajes,
      navigatorKey: navegador,
      theme: catalogTheme(),
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox(),
          if (bloqueada) PantallaBloqueo(alDesbloquear: alDesbloquear ?? () {}),
        ],
      ),
      home: const InicioScreen(),
    );
  }
}
