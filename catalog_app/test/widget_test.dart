import 'dart:io';

import 'package:catalog/app_scope.dart';
import 'package:catalog/data/base.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/fotos.dart';
import 'package:catalog/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  testWidgets('el inicio muestra el gasto del mes y el botón de nueva compra', (tester) async {
    late CatalogDb base;
    await tester.runAsync(() async {
      base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
    });
    await tester.pumpWidget(AppScope(
      base: base,
      compras: ComprasRepo(base),
      fotos: FotosStore(Directory.systemTemp),
      child: const CatalogApp(),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();

    expect(find.text('Nueva compra'), findsOneWidget);
    expect(find.text('Gastado este mes'), findsOneWidget);
    expect(find.text(r'$0'), findsOneWidget);
    await tester.runAsync(base.cerrar);
  });
}
