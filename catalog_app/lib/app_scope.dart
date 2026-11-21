import 'package:material_ui/material_ui.dart';

import 'data/base.dart';
import 'data/compras_repo.dart';
import 'data/fotos.dart';

/// Da acceso a la base de datos y a las fotos desde cualquier pantalla.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.base,
    required this.compras,
    required this.fotos,
    required super.child,
  });

  final CatalogDb base;
  final ComprasRepo compras;
  final FotosStore fotos;

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
