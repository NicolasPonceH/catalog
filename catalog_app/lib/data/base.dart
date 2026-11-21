import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'migraciones.dart';

/// Base de datos local del teléfono (funciona sin internet).
class CatalogDb {
  CatalogDb._(this.db);

  final Database db;
  final _cambios = StreamController<void>.broadcast();

  /// Avisa cada vez que se guarda algo, para refrescar las pantallas.
  Stream<void> get cambios => _cambios.stream;

  void avisarCambio() {
    if (!_cambios.isClosed) _cambios.add(null);
  }

  static Future<CatalogDb> abrir({String? ruta, DatabaseFactory? fabrica}) async {
    final f = fabrica ?? databaseFactory;
    final camino = ruta ?? p.join(await f.getDatabasesPath(), 'catalog.db');
    final db = await f.openDatabase(
      camino,
      options: OpenDatabaseOptions(
        version: versionBaseDatos,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrar(db, 0, version),
        onUpgrade: _migrar,
      ),
    );
    return CatalogDb._(db);
  }

  static Future<void> _migrar(Database db, int desde, int hasta) async {
    for (var v = desde + 1; v <= hasta; v++) {
      for (final sql in migraciones[v]!) {
        await db.execute(sql);
      }
    }
  }

  Future<void> cerrar() async {
    await _cambios.close();
    await db.close();
  }
}
