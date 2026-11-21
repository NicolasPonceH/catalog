import 'package:sqflite/sqflite.dart';

import '../domain/codigo.dart';
import '../domain/formato.dart';
import 'base.dart';
import 'compra.dart';

class Lote {
  const Lote({
    required this.id,
    required this.nombre,
    required this.creadoEn,
    this.cerradoEn,
    required this.notas,
  });

  factory Lote.deFila(Map<String, Object?> f) => Lote(
        id: f['id']! as int,
        nombre: f['nombre']! as String,
        creadoEn: deMs(f['creado_en']),
        cerradoEn: deMsOpcional(f['cerrado_en']),
        notas: f['notas']! as String,
      );

  final int id;
  final String nombre;
  final DateTime creadoEn;
  final DateTime? cerradoEn;
  final String notas;

  bool get cerrado => cerradoEn != null;
}

class LoteConTotal {
  const LoteConTotal(this.lote, this.resumen);

  final Lote lote;
  final Resumen resumen;
}

class ItemLote {
  const ItemLote(this.compra, this.escaneadoEn);

  final Compra compra;
  final DateTime escaneadoEn;
}

enum ResultadoEscaneo { agregado, yaEstaba, anulada, noExiste, noEsCodigo }

/// Lotes: grupos de catalíticos escaneados (por ejemplo, los que se entregan juntos).
class LotesRepo {
  LotesRepo(this.base, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final CatalogDb base;
  final DateTime Function() _reloj;

  Database get _db => base.db;

  Future<Lote> crear({String? nombre}) async {
    final ahora = _reloj();
    final id = await _db.insert('lotes', {
      'nombre': (nombre == null || nombre.trim().isEmpty) ? 'Lote ${fechaHora(ahora)}' : nombre.trim(),
      'creado_en': ms(ahora),
    });
    base.avisarCambio();
    return (await obtener(id))!;
  }

  Future<Lote?> obtener(int id) async {
    final filas = await _db.query('lotes', where: 'id = ?', whereArgs: [id]);
    return filas.isEmpty ? null : Lote.deFila(filas.first);
  }

  /// Todos los lotes, el más nuevo primero, con cantidad y total pagado.
  Future<List<LoteConTotal>> listar() async {
    final filas = await _db.rawQuery('''
      SELECT l.*,
        COUNT(c.id) AS cantidad,
        COALESCE(SUM(c.precio), 0) AS total
      FROM lotes l
      LEFT JOIN lote_items i ON i.lote_id = l.id
      LEFT JOIN compras c ON c.id = i.compra_id AND c.estado = 'activa'
      GROUP BY l.id
      ORDER BY l.creado_en DESC, l.id DESC
    ''');
    return [
      for (final f in filas)
        LoteConTotal(Lote.deFila(f), Resumen(f['cantidad']! as int, f['total']! as int)),
    ];
  }

  /// Agrega al lote el catalítico del código escaneado (QR o código de barras).
  Future<(ResultadoEscaneo, Compra?)> agregarEscaneado(int loteId, String textoLeido) async {
    final codigo = leerCodigoEscaneado(textoLeido);
    if (codigo == null) return (ResultadoEscaneo.noEsCodigo, null);
    final filas = await _db.query('compras', where: 'codigo = ?', whereArgs: [codigo]);
    if (filas.isEmpty) return (ResultadoEscaneo.noExiste, null);
    final compra = Compra.deFila(filas.first);
    if (compra.anulada) return (ResultadoEscaneo.anulada, compra);
    final id = await _db.insert(
      'lote_items',
      {'lote_id': loteId, 'compra_id': compra.id, 'escaneado_en': ms(_reloj())},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (id == 0) return (ResultadoEscaneo.yaEstaba, compra);
    base.avisarCambio();
    return (ResultadoEscaneo.agregado, compra);
  }

  /// Catalíticos del lote, el último escaneado primero.
  Future<List<ItemLote>> items(int loteId) async {
    final filas = await _db.rawQuery('''
      SELECT c.*, i.escaneado_en AS escaneado_en_lote
      FROM lote_items i JOIN compras c ON c.id = i.compra_id
      WHERE i.lote_id = ?
      ORDER BY i.escaneado_en DESC, c.id DESC
    ''', [loteId]);
    return [for (final f in filas) ItemLote(Compra.deFila(f), deMs(f['escaneado_en_lote']))];
  }

  /// Cantidad y total pagado del lote (solo compras activas).
  Future<Resumen> resumen(int loteId) async {
    final filas = await _db.rawQuery('''
      SELECT COUNT(*) AS c, COALESCE(SUM(c.precio), 0) AS t
      FROM lote_items i JOIN compras c ON c.id = i.compra_id
      WHERE i.lote_id = ? AND c.estado = 'activa'
    ''', [loteId]);
    return Resumen(filas.first['c']! as int, filas.first['t']! as int);
  }

  Future<void> quitar(int loteId, int compraId) async {
    await _db.delete('lote_items', where: 'lote_id = ? AND compra_id = ?', whereArgs: [loteId, compraId]);
    base.avisarCambio();
  }

  Future<void> cerrar(int loteId) async {
    await _db.update('lotes', {'cerrado_en': ms(_reloj())}, where: 'id = ?', whereArgs: [loteId]);
    base.avisarCambio();
  }

  Future<void> reabrir(int loteId) async {
    await _db.update('lotes', {'cerrado_en': null}, where: 'id = ?', whereArgs: [loteId]);
    base.avisarCambio();
  }

  Future<void> renombrar(int loteId, String nombre) async {
    if (nombre.trim().isEmpty) return;
    await _db.update('lotes', {'nombre': nombre.trim()}, where: 'id = ?', whereArgs: [loteId]);
    base.avisarCambio();
  }

  /// Borra el lote (solo la agrupación; las compras no se tocan).
  Future<void> eliminar(int loteId) async {
    await _db.delete('lotes', where: 'id = ?', whereArgs: [loteId]);
    base.avisarCambio();
  }
}
