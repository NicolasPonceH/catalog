import 'package:sqflite/sqflite.dart';

import '../domain/formato.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import 'base.dart';
import 'compra.dart';

/// Tipos de discrepancia / observación que puede marcar el Supervisor con 1 toque.
enum TipoObservacionSupervisor {
  ninguna,
  ceramicaPartida,
  nivelMenor,
  noCoincide,
  precioObservado,
  otra,
}

extension TipoObservacionSupervisorExt on TipoObservacionSupervisor {
  String get claveDb => switch (this) {
        TipoObservacionSupervisor.ninguna => '',
        TipoObservacionSupervisor.ceramicaPartida => 'ceramica_partida',
        TipoObservacionSupervisor.nivelMenor => 'nivel_menor',
        TipoObservacionSupervisor.noCoincide => 'no_coincide',
        TipoObservacionSupervisor.precioObservado => 'precio_observado',
        TipoObservacionSupervisor.otra => 'otra',
      };

  static TipoObservacionSupervisor deClaveDb(Object? v) => switch (v) {
        'ceramica_partida' => TipoObservacionSupervisor.ceramicaPartida,
        'nivel_menor' => TipoObservacionSupervisor.nivelMenor,
        'no_coincide' => TipoObservacionSupervisor.noCoincide,
        'precio_observado' => TipoObservacionSupervisor.precioObservado,
        'otra' => TipoObservacionSupervisor.otra,
        _ => TipoObservacionSupervisor.ninguna,
      };

  String get etiqueta => switch (this) {
        TipoObservacionSupervisor.ninguna => tr('Sin observación', 'No discrepancy'),
        TipoObservacionSupervisor.ceramicaPartida =>
          tr('Cerámica partida / fundida', 'Cracked / melted honeycomb'),
        TipoObservacionSupervisor.nivelMenor =>
          tr('Menos cerámica (3/4 o medio)', 'Less honeycomb (3/4 or half)'),
        TipoObservacionSupervisor.noCoincide =>
          tr('No coincide con foto / código', 'Does not match photo / code'),
        TipoObservacionSupervisor.precioObservado =>
          tr('Precio observado / alto', 'Flagged / high price'),
        TipoObservacionSupervisor.otra => tr('Otra diferencia', 'Other discrepancy'),
      };
}

class ObservacionSupervisor {
  const ObservacionSupervisor({
    this.tipo = TipoObservacionSupervisor.ninguna,
    this.nota = '',
  });

  static const vacia = ObservacionSupervisor();

  final TipoObservacionSupervisor tipo;
  final String nota;

  bool get activa => tipo != TipoObservacionSupervisor.ninguna || nota.trim().isNotEmpty;

  String get resumen {
    if (!activa) return '';
    final n = nota.trim();
    if (tipo == TipoObservacionSupervisor.ninguna) return n;
    if (n.isEmpty) return tipo.etiqueta;
    return '${tipo.etiqueta}: $n';
  }

  Map<String, dynamic> aJson() => {'tipo': tipo.claveDb, 'nota': nota.trim()};

  factory ObservacionSupervisor.deJson(Map<String, dynamic> j) => ObservacionSupervisor(
        tipo: TipoObservacionSupervisorExt.deClaveDb(j['tipo']),
        nota: (j['nota'] as String? ?? '').trim(),
      );
}

/// Referencia a un lote de supervisor donde un código ya fue revisado y bloqueado.
class PrevioLoteSupervisor {
  const PrevioLoteSupervisor({
    required this.codigo,
    required this.loteId,
    required this.loteNombre,
    required this.cerradoEn,
  });

  final String codigo;
  final int loteId;
  final String loteNombre;
  final DateTime cerradoEn;
}

class BorradorItemSupervisor {
  const BorradorItemSupervisor({
    required this.codigo,
    this.compra,
    this.escaneadoEn,
    this.observacion = ObservacionSupervisor.vacia,
  });

  final String codigo;
  final Compra? compra;
  final DateTime? escaneadoEn;
  final ObservacionSupervisor observacion;
}

class ItemLoteSupervisor {
  const ItemLoteSupervisor({
    required this.id,
    required this.loteSupId,
    required this.codigo,
    this.fechaCompra,
    required this.vendedor,
    required this.tipo,
    required this.llenado,
    required this.codigoFabrica,
    required this.autos,
    required this.precio,
    this.escaneadoEn,
    required this.observacion,
  });

  factory ItemLoteSupervisor.deFila(Map<String, Object?> f) => ItemLoteSupervisor(
        id: f['id']! as int,
        loteSupId: f['lote_sup_id']! as int,
        codigo: f['codigo']! as String,
        fechaCompra: deMsOpcional(f['fecha_compra']),
        vendedor: f['vendedor']! as String,
        tipo: f['tipo']! as String,
        llenado: NivelLlenadoEtiqueta.deClaveDb(f['llenado']),
        codigoFabrica: f['codigo_fabrica']! as String,
        autos: f['autos']! as String,
        precio: (f['precio'] as num?)?.toInt() ?? 0,
        escaneadoEn: deMsOpcional(f['escaneado_en']),
        observacion: ObservacionSupervisor(
          tipo: TipoObservacionSupervisorExt.deClaveDb(f['observacion_tipo']),
          nota: f['observacion_nota'] as String? ?? '',
        ),
      );

  final int id;
  final int loteSupId;
  final String codigo;
  final DateTime? fechaCompra;
  final String vendedor;
  final String tipo;
  final NivelLlenado llenado;
  final String codigoFabrica;
  final String autos;
  final int precio;
  final DateTime? escaneadoEn;
  final ObservacionSupervisor observacion;
}

class LoteSupervisor {
  const LoteSupervisor({
    required this.id,
    required this.nombre,
    required this.comprador,
    required this.prefijo,
    required this.rangoTexto,
    required this.creadoEn,
    required this.cerradoEn,
    required this.notas,
    required this.cantidad,
    required this.conObservacion,
    required this.totalVerificado,
  });

  factory LoteSupervisor.deFila(Map<String, Object?> f) => LoteSupervisor(
        id: f['id']! as int,
        nombre: f['nombre']! as String,
        comprador: f['comprador']! as String,
        prefijo: f['prefijo']! as String,
        rangoTexto: f['rango_texto']! as String,
        creadoEn: deMs(f['creado_en']),
        cerradoEn: deMs(f['cerrado_en']),
        notas: f['notas']! as String,
        cantidad: (f['cantidad'] as num?)?.toInt() ?? 0,
        conObservacion: (f['con_obs'] as num?)?.toInt() ?? 0,
        totalVerificado: (f['total_verif'] as num?)?.toInt() ?? 0,
      );

  final int id;
  final String nombre;
  final String comprador;
  final String prefijo;
  final String rangoTexto;
  final DateTime creadoEn;
  final DateTime cerradoEn;
  final String notas;
  final int cantidad;
  final int conObservacion;
  final int totalVerificado;

  String get codigoLote {
    final f = cerradoEn;
    final yy = (f.year % 100).toString().padLeft(2, '0');
    final mm = f.month.toString().padLeft(2, '0');
    final dd = f.day.toString().padLeft(2, '0');
    return 'SUP-$yy$mm$dd-${id.toString().padLeft(4, '0')}';
  }
}

/// Repositorio de Lotes de Supervisor en la base permanente del celular del supervisor.
/// Garantiza que ningún catalítico cerrado en un lote de supervisor se repita en otro.
class SupervisorRepo {
  SupervisorRepo(this.base, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final CatalogDb base;
  final DateTime Function() _reloj;

  Database get _db => base.db;

  /// Mapa `codigo -> PrevioLoteSupervisor` con todos los catalíticos ya cerrados en lotes de supervisor.
  Future<Map<String, PrevioLoteSupervisor>> mapaYaRevisados() async {
    final filas = await _db.rawQuery('''
      SELECT i.codigo, l.id AS lote_id, l.nombre AS lote_nombre, l.cerrado_en
      FROM lotes_supervisor_items i
      JOIN lotes_supervisor l ON l.id = i.lote_sup_id
    ''');
    return {
      for (final f in filas)
        (f['codigo']! as String): PrevioLoteSupervisor(
          codigo: f['codigo']! as String,
          loteId: f['lote_id']! as int,
          loteNombre: f['lote_nombre']! as String,
          cerradoEn: deMs(f['cerrado_en']),
        ),
    };
  }

  Future<PrevioLoteSupervisor?> buscarYaRevisado(String codigo) async {
    final filas = await _db.rawQuery('''
      SELECT i.codigo, l.id AS lote_id, l.nombre AS lote_nombre, l.cerrado_en
      FROM lotes_supervisor_items i
      JOIN lotes_supervisor l ON l.id = i.lote_sup_id
      WHERE i.codigo = ?
      LIMIT 1
    ''', [codigo]);
    if (filas.isEmpty) return null;
    final f = filas.first;
    return PrevioLoteSupervisor(
      codigo: f['codigo']! as String,
      loteId: f['lote_id']! as int,
      loteNombre: f['lote_nombre']! as String,
      cerradoEn: deMs(f['cerrado_en']),
    );
  }

  /// Guarda un nuevo Lote de Supervisor con las piezas verificadas.
  /// Lanza [DatosInvalidos] si no hay piezas nuevas o si alguna ya está en otro lote de supervisor.
  Future<LoteSupervisor> guardarLote({
    required String nombre,
    String comprador = '',
    String prefijo = '',
    String rangoTexto = '',
    String notas = '',
    required List<BorradorItemSupervisor> items,
  }) async {
    if (items.isEmpty) {
      throw DatosInvalidos(tr('Escanea al menos un catalítico antes de guardar el lote',
          'Scan at least one converter before saving the batch'));
    }
    final ahora = _reloj();
    final yaEnLote = await mapaYaRevisados();
    for (final it in items) {
      final prev = yaEnLote[it.codigo];
      if (prev != null) {
        throw DatosInvalidos(
          tr(
            '${it.codigo} ya fue guardado en «${prev.loteNombre}» (${fechaCorta(prev.cerradoEn)}). No se puede repetir.',
            '${it.codigo} was already saved in "${prev.loteNombre}" (${fechaCorta(prev.cerradoEn)}). Cannot repeat.',
          ),
        );
      }
    }

    final nomLimpio = nombre.trim().isEmpty
        ? '${tr('Lote Supervisor', 'Supervisor Batch')} ${fechaHora(ahora)}'
        : nombre.trim();

    final loteId = await _db.transaction((txn) async {
      final id = await txn.insert('lotes_supervisor', {
        'nombre': nomLimpio,
        'comprador': comprador.trim(),
        'prefijo': prefijo.trim(),
        'rango_texto': rangoTexto.trim(),
        'creado_en': ms(ahora),
        'cerrado_en': ms(ahora),
        'notas': notas.trim(),
      });
      for (final it in items) {
        final c = it.compra;
        await txn.insert('lotes_supervisor_items', {
          'lote_sup_id': id,
          'codigo': it.codigo,
          'fecha_compra': c != null ? ms(c.fechaCompra) : null,
          'vendedor': c?.vendedor ?? '',
          'tipo': c?.tipo ?? '',
          'llenado': (c?.llenado ?? NivelLlenado.entero).claveDb,
          'codigo_fabrica': c?.codigoFabrica ?? '',
          'autos': c?.autos ?? '',
          'precio': (c == null || c.anulada) ? 0 : c.precio,
          'escaneado_en': it.escaneadoEn != null ? ms(it.escaneadoEn!) : ms(ahora),
          'observacion_tipo': it.observacion.tipo.claveDb,
          'observacion_nota': it.observacion.nota.trim(),
        });
      }
      return id;
    });

    base.avisarCambio();
    return (await obtenerLote(loteId))!;
  }

  Future<LoteSupervisor?> obtenerLote(int id) async {
    final filas = await _db.rawQuery('''
      SELECT l.*,
        COUNT(i.id) AS cantidad,
        SUM(CASE WHEN i.observacion_tipo != '' OR i.observacion_nota != '' THEN 1 ELSE 0 END) AS con_obs,
        COALESCE(SUM(i.precio), 0) AS total_verif
      FROM lotes_supervisor l
      LEFT JOIN lotes_supervisor_items i ON i.lote_sup_id = l.id
      WHERE l.id = ?
      GROUP BY l.id
    ''', [id]);
    return filas.isEmpty ? null : LoteSupervisor.deFila(filas.first);
  }

  Future<List<LoteSupervisor>> listarLotes() async {
    final filas = await _db.rawQuery('''
      SELECT l.*,
        COUNT(i.id) AS cantidad,
        COALESCE(SUM(CASE WHEN i.observacion_tipo != '' OR i.observacion_nota != '' THEN 1 ELSE 0 END), 0) AS con_obs,
        COALESCE(SUM(i.precio), 0) AS total_verif
      FROM lotes_supervisor l
      LEFT JOIN lotes_supervisor_items i ON i.lote_sup_id = l.id
      GROUP BY l.id
      ORDER BY l.cerrado_en DESC, l.id DESC
    ''');
    return filas.map(LoteSupervisor.deFila).toList();
  }

  Future<List<ItemLoteSupervisor>> itemsDeLote(int loteSupId) async {
    final filas = await _db.query(
      'lotes_supervisor_items',
      where: 'lote_sup_id = ?',
      whereArgs: [loteSupId],
      orderBy: 'escaneado_en DESC, id DESC',
    );
    return filas.map(ItemLoteSupervisor.deFila).toList();
  }

  Future<void> eliminarLote(int loteSupId) async {
    await _db.delete('lotes_supervisor', where: 'id = ?', whereArgs: [loteSupId]);
    base.avisarCambio();
  }
}
