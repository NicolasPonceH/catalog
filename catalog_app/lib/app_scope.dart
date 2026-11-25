import 'package:material_ui/material_ui.dart';

import 'backup/respaldo.dart';
import 'data/base.dart';
import 'data/compras_repo.dart';
import 'data/dispositivo.dart';
import 'data/fotos.dart';
import 'data/lotes_repo.dart';
import 'data/sesiones.dart';
import 'data/supervisor_repo.dart';

/// Acciones que cambian la base de datos abierta (las hace la raíz de la app).
abstract class AccionesApp {
  Future<void> abrirSesion(Sesion sesion, {String? mensaje});

  /// Guarda los datos recibidos como sesión de revisión y la abre.
  Future<void> recibirRevision(ContenidoRespaldo contenido);

  Future<void> eliminarRevision(Sesion sesion);

  /// Reemplaza la base de la sesión de compra (al restaurar un respaldo).
  /// [escribir] recibe la ruta de la base y escribe los archivos nuevos
  /// mientras la base está cerrada.
  Future<void> reemplazarDatos(Future<void> Function(String rutaBase) escribir, {String? mensaje});
}

/// Da acceso a la base de datos, las fotos y la sesión desde cualquier pantalla.
class AppScope extends InheritedWidget {
  AppScope({
    super.key,
    required this.base,
    required this.fotos,
    this.sesion,
    this.sesiones,
    this.dispositivo,
    this.acciones,
    required super.child,
  })  : compras = ComprasRepo(base),
        lotes = LotesRepo(base),
        supervisor = SupervisorRepo(base);

  final CatalogDb base;
  final ComprasRepo compras;
  final LotesRepo lotes;
  final SupervisorRepo supervisor;
  final FotosStore fotos;
  final Sesion? sesion;
  final Sesiones? sesiones;
  final AjustesDispositivo? dispositivo;
  final AccionesApp? acciones;

  /// En una sesión de revisión no se registran ni corrigen compras.
  bool get soloLectura => sesion?.esRevision ?? false;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  static AppScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>();

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      base != oldWidget.base || sesion?.id != oldWidget.sesion?.id;
}

Future<T?> abrir<T>(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => pantalla));

void avisar(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));
}
