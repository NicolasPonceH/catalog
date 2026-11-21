import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app_scope.dart';
import 'data/base.dart';
import 'data/compras_repo.dart';
import 'data/fotos.dart';
import 'features/inicio_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final base = await CatalogDb.abrir();
  final fotos = await FotosStore.abrir();
  runApp(AppScope(
    base: base,
    compras: ComprasRepo(base),
    fotos: fotos,
    child: const CatalogApp(),
  ));
}

class CatalogApp extends StatelessWidget {
  const CatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CataLog',
      debugShowCheckedModeBanner: false,
      theme: catalogTheme(),
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const InicioScreen(),
    );
  }
}
