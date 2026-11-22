import 'package:material_ui/material_ui.dart';

import 'data/base.dart';
import 'data/compras_repo.dart';
import 'data/fotos.dart';
import 'data/lotes_repo.dart';

/// Reemplaza la base de datos (al restaurar un respaldo). Recibe una función
/// que escribe los archivos nuevos mientras la base está cerrada.
typedef ReemplazarDatos = Future<void> Function(
  Future<void> Function(String rutaBase) escribir, {
  String? mensaje,
});

/// Da acceso a la base de datos y a las fotos desde cualquier pantalla.
class AppScope extends InheritedWidget {
  AppScope({
    super.key,
    required this.base,
    required this.fotos,
    this.reemplazarDatos,
    required super.child,
  })  : compras = ComprasRepo(base),
        lotes = LotesRepo(base);

  final CatalogDb base;
  final ComprasRepo compras;
  final LotesRepo lotes;
  final FotosStore fotos;
  final ReemplazarDatos? reemplazarDatos;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => base != oldWidget.base;
}

Future<T?> abrir<T>(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => pantalla));

void avisar(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensaje)));
}
