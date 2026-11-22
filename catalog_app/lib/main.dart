import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'data/base.dart';
import 'data/fotos.dart';
import 'features/inicio_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final base = await CatalogDb.abrir();
  final fotos = await FotosStore.abrir();
  runApp(CatalogRoot(base: base, fotos: fotos));
}

/// Raíz de la app. Guarda la base de datos abierta y permite cambiarla al
/// restaurar un respaldo (la app vuelve al Inicio con los datos nuevos).
class CatalogRoot extends StatefulWidget {
  const CatalogRoot({super.key, required this.base, required this.fotos});

  final CatalogDb base;
  final FotosStore fotos;

  @override
  State<CatalogRoot> createState() => _CatalogRootState();
}

class _CatalogRootState extends State<CatalogRoot> {
  late CatalogDb _base = widget.base;
  GlobalKey<ScaffoldMessengerState> _mensajes = GlobalKey();

  Future<void> _reemplazarDatos(
    Future<void> Function(String rutaBase) escribir, {
    String? mensaje,
  }) async {
    final ruta = _base.db.path;
    await _base.cerrar();
    Object? error;
    try {
      await escribir(ruta);
    } catch (e) {
      error = e;
    }
    final nueva = await CatalogDb.abrir(ruta: ruta);
    if (!mounted) return;
    setState(() {
      _base = nueva;
      _mensajes = GlobalKey();
    });
    final texto = error == null ? mensaje : 'No se pudo restaurar: $error';
    if (texto != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mensajes.currentState?.showSnackBar(SnackBar(content: Text(texto)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      base: _base,
      fotos: widget.fotos,
      reemplazarDatos: _reemplazarDatos,
      // Con otra base, toda la app se arma de nuevo desde el Inicio.
      child: CatalogApp(key: ObjectKey(_base), mensajes: _mensajes),
    );
  }
}

class CatalogApp extends StatelessWidget {
  const CatalogApp({super.key, this.mensajes});

  final GlobalKey<ScaffoldMessengerState>? mensajes;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CataLog',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: mensajes,
      theme: catalogTheme(),
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const InicioScreen(),
    );
  }
}
