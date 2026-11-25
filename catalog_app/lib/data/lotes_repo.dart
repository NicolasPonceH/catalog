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
    this.montoRecibido,
    required this.notas,
  });

  factory Lote.deFila(Map<String, Object?> f) => Lote(
        id: f['id']! as int,
        nombre: f['nombre']! as String,
        creadoEn: deMs(f['creado_en']),
        cerradoEn: deMsOpcional(f['cerrado_en']),
        montoRecibido: (f['monto_recibido'] as num?)?.toInt(),
        notas: f['notas']! as String,
      );

  final int id;
  final String nombre;
  final DateTime creadoEn;
  final DateTime? cerradoEn;

  /// Cuánto se recibió al entregar o vender el lote (null si todavía no se anota).
  final int? montoRecibido;
  final String notas;

  bool get cerrado => cerradoEn != null;
}

class LoteConTotal {
  const LoteConTotal(this.lote, this.resumen);

  final Lote lote;
  final Resumen resumen;

  /// Ganancia neta (venta menos costo pagado) si se registró cuánto se recibió.
  int? get ganancia => lote.montoRecibido == null ? null : lote.montoRecibido! - resumen.total;
}

class ItemLote {
  const ItemLote(this.compra, this.escaneadoEn);

  final Compra compra;
  final DateTime escaneadoEn;
}

enum ResultadoEscaneo { agregado, yaEstaba, enOtroLote, anulada, noExiste, noEsCodigo }

/// Lotes: grupos de catalíticos escaneados (por ejemplo, los que se entregan juntos).
/// Un mismo catalítico nunca puede repetirse en otro lote distinto.
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

  /// Devuelve el lote en el que ya está guardada [compraId] (excluyendo opcionalmente [excluirLoteId]).
  Future<Lote?> loteDeCompra(int compraId, {int? excluirLoteId}) async {
    final filas = await _db.rawQuery('''
      SELECT l.*
      FROM lote_items i
      JOIN lotes l ON l.id = i.lote_id
      WHERE i.compra_id = ?${excluirLoteId != null ? ' AND i.lote_id != ?' : ''}
      ORDER BY l.creado_en DESC, l.id DESC
      LIMIT 1
    ''', [compraId, ?excluirLoteId]);
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
  /// Bloquea tanto si ya estaba en este lote como si ya pertenece a otro lote distinto.
  Future<(ResultadoEscaneo, Compra?)> agregarEscaneado(int loteId, String textoLeido) async {
    final codigo = leerCodigoEscaneado(textoLeido);
    if (codigo == null) return (ResultadoEscaneo.noEsCodigo, null);
    final filas = await _db.query('compras', where: 'codigo = ?', whereArgs: [codigo]);
    if (filas.isEmpty) return (ResultadoEscaneo.noExiste, null);
    final compra = Compra.deFila(filas.first);
    if (compra.anulada) return (ResultadoEscaneo.anulada, compra);

    // 1. ¿Ya está en este mismo lote?
    final enMismo = await _db.query(
      'lote_items',
      columns: ['lote_id'],
      where: 'lote_id = ? AND compra_id = ?',
      whereArgs: [loteId, compra.id],
      limit: 1,
    );
    if (enMismo.isNotEmpty) return (ResultadoEscaneo.yaEstaba, compra);

    // 2. ¿Ya fue incluido en otro lote anterior o distinto?
    final otroLote = await loteDeCompra(compra.id, excluirLoteId: loteId);
    if (otroLote != null) return (ResultadoEscaneo.enOtroLote, compra);

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

  Future<void> cerrar(int loteId, {int? montoRecibido, bool actualizarMonto = false}) async {
    await _db.update(
      'lotes',
      {
        'cerrado_en': ms(_reloj()),
        if (actualizarMonto) 'monto_recibido': montoRecibido,
      },
      where: 'id = ?',
      whereArgs: [loteId],
    );
    base.avisarCambio();
  }

  /// Registra o borra cuánto se recibió por el lote completo.
  Future<void> guardarMontoRecibido(int loteId, int? montoRecibido) async {
    await _db.update('lotes', {'monto_recibido': montoRecibido}, where: 'id = ?', whereArgs: [loteId]);
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
