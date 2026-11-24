import 'package:sqflite/sqflite.dart';

import '../domain/codigo.dart';
import '../domain/periodos.dart';
import '../i18n.dart';
import 'base.dart';
import 'compra.dart';

/// Validación común para crear y editar. Devuelve el error o null.
String? validarDatosCompra(DatosCompra d, DateTime ahora) {
  final fecha = validarFechaCompra(d.fechaCompra, ahora);
  if (fecha != null) return fecha;
  if (d.vendedor.trim().isEmpty) return tr('Falta el nombre del vendedor', 'Seller name is required');
  if (d.precio < 0) return tr('El precio no puede ser negativo', 'Price cannot be negative');
  return null;
}

/// Todo lo que se lee y guarda sobre las compras.
class ComprasRepo {
  ComprasRepo(this.base, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  final CatalogDb base;
  final DateTime Function() _reloj;

  Database get _db => base.db;

  // ---------- Ajustes ----------

  Future<String?> leerAjuste(String clave) async {
    final filas = await _db.query('ajustes', where: 'clave = ?', whereArgs: [clave]);
    return filas.isEmpty ? null : filas.first['valor']! as String;
  }

  Future<void> guardarAjuste(String clave, String valor) async {
    await _db.insert(
      'ajustes',
      {'clave': clave, 'valor': valor},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    base.avisarCambio();
  }

  Future<String> prefijo() async => (await leerAjuste('prefijo')) ?? prefijoPorDefecto;

  // ---------- Respaldo ----------

  static const _claveUltimoRespaldo = 'ultimo_respaldo';

  Future<void> registrarRespaldo() => guardarAjuste(_claveUltimoRespaldo, _reloj().toIso8601String());

  Future<DateTime?> ultimoRespaldo() async =>
      DateTime.tryParse(await leerAjuste(_claveUltimoRespaldo) ?? '');

  Future<int> contarCompras() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM compras')) ?? 0;

  /// Mensaje para recordar el respaldo, o null si no hace falta todavía.
  /// Aparece si hay compras sin respaldar y pasó una semana (o un día si nunca
  /// se respaldó), o si se acumularon muchas.
  Future<String?> avisoRespaldo() async {
    final ultimo = await ultimoRespaldo();
    final filas = await _db.rawQuery(
      'SELECT COUNT(*) AS n, MIN(creado_en) AS primera FROM compras'
      '${ultimo != null ? ' WHERE creado_en > ?' : ''}',
      ultimo != null ? [ms(ultimo)] : null,
    );
    final n = filas.first['n']! as int;
    if (n == 0) return null;
    final ahora = _reloj();
    final compras = n == 1 ? tr('1 compra', '1 purchase') : tr('$n compras', '$n purchases');
    if (ultimo == null) {
      final primera = deMs(filas.first['primera']);
      if (ahora.difference(primera) >= const Duration(days: 1) || n >= 10) {
        return tr(
          'Todavía no has hecho un respaldo: $compras están solo en este teléfono.',
          'You haven’t backed up yet: $compras live only on this phone.',
        );
      }
      return null;
    }
    final dias = ahora.difference(ultimo).inDays;
    if (dias >= 7 || n >= 20) {
      return tr(
        'Hace $dias días que no respaldas y hay $compras sin respaldar.',
        'It’s been $dias days since your last backup and $compras are not backed up.',
      );
    }
    return null;
  }

  // ---------- Guardar ----------

  /// Guarda una compra nueva y le asigna su código con la FECHA DE COMPRA.
  Future<Compra> crear(DatosCompra d) async {
    final ahora = _reloj();
    final error = validarDatosCompra(d, ahora);
    if (error != null) throw DatosInvalidos(error);
    final pref = await prefijo();

    final id = await _db.transaction((txn) async {
      final dia = diaClave(d.fechaCompra);
      final contador = await txn.query('contador_codigos', where: 'dia = ?', whereArgs: [dia]);
      var numero = contador.isEmpty ? 0 : contador.first['ultimo']! as int;
      String codigo;
      while (true) {
        numero++;
        codigo = formatearCodigo(pref, d.fechaCompra, numero);
        final existe = await txn.query('compras',
            columns: ['id'], where: 'codigo = ?', whereArgs: [codigo]);
        if (existe.isEmpty) break;
      }
      if (contador.isEmpty) {
        await txn.insert('contador_codigos', {'dia': dia, 'ultimo': numero});
      } else {
        await txn.update('contador_codigos', {'ultimo': numero},
            where: 'dia = ?', whereArgs: [dia]);
      }
      return txn.insert('compras', {
        ...d.aFila(),
        'codigo': codigo,
        'creado_en': ms(ahora),
        'actualizado_en': ms(ahora),
      });
    });

    base.avisarCambio();
    return (await obtener(id))!;
  }

  /// Corrige una compra. El código no cambia (ya puede estar impreso).
  Future<void> actualizar(int id, DatosCompra d) async {
    final ahora = _reloj();
    final error = validarDatosCompra(d, ahora);
    if (error != null) throw DatosInvalidos(error);
    final previa = await obtener(id);
    if (previa == null) throw DatosInvalidos('La compra ya no existe');
    final cambiaFecha = ms(previa.fechaCompra) != ms(d.fechaCompra);
    await _db.update(
      'compras',
      {
        ...d.aFila(),
        'actualizado_en': ms(ahora),
        if (cambiaFecha) 'fecha_compra_editada_en': ms(ahora),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    base.avisarCambio();
  }

  /// Las compras no se borran: se anulan y salen de los totales.
  Future<void> anular(int id, String motivo) async {
    await _db.update(
      'compras',
      {
        'estado': 'anulada',
        'anulada_en': ms(_reloj()),
        'motivo_anulacion': motivo.trim(),
        'actualizado_en': ms(_reloj()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    base.avisarCambio();
  }

  Future<void> reactivar(int id) async {
    await _db.update(
      'compras',
      {
        'estado': 'activa',
        'anulada_en': null,
        'motivo_anulacion': '',
        'actualizado_en': ms(_reloj()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    base.avisarCambio();
  }

  /// Suma una impresión del sticker.
  Future<void> marcarImpresion(int id) async {
    await _db.rawUpdate('UPDATE compras SET impresiones = impresiones + 1 WHERE id = ?', [id]);
    base.avisarCambio();
  }

  // ---------- Leer ----------

  Future<Compra?> obtener(int id) async {
    final filas = await _db.query('compras', where: 'id = ?', whereArgs: [id]);
    return filas.isEmpty ? null : Compra.deFila(filas.first);
  }

  Future<Compra?> buscarPorCodigo(String codigo) async {
    final filas = await _db.query('compras', where: 'codigo = ?', whereArgs: [codigo]);
    return filas.isEmpty ? null : Compra.deFila(filas.first);
  }

  /// Cantidad y total de las compras activas cuya FECHA DE COMPRA cae en el período.
  Future<Resumen> resumen(Periodo p) async {
    final filas = await _db.rawQuery(
      'SELECT COUNT(*) AS c, COALESCE(SUM(precio), 0) AS t FROM compras '
      "WHERE estado = 'activa' AND fecha_compra >= ? AND fecha_compra < ?",
      [ms(p.desde), ms(p.hasta)],
    );
    return Resumen(filas.first['c']! as int, filas.first['t']! as int);
  }

  Future<List<Compra>> ultimas(int limite) async {
    final filas = await _db.query('compras',
        orderBy: 'fecha_compra DESC, id DESC', limit: limite);
    return filas.map(Compra.deFila).toList();
  }

  /// Historial ordenado por fecha de compra, de la más nueva a la más vieja.
  Future<List<Compra>> historial(FiltroHistorial f) async {
    final donde = <String>[];
    final args = <Object?>[];
    final p = f.periodo;
    if (p != null) {
      donde.add('fecha_compra >= ? AND fecha_compra < ?');
      args.addAll([ms(p.desde), ms(p.hasta)]);
    }
    if (f.material != null) {
      donde.add('material = ?');
      args.add(f.material!.name);
    }
    if (f.soloSinImprimir) {
      donde.add("estado = 'activa' AND impresiones = 0");
    }
    final texto = f.texto.trim().replaceAll(RegExp('[%_]'), '');
    if (texto.isNotEmpty) {
      final like = '%$texto%';
      donde.add('(codigo LIKE ? OR vendedor LIKE ? OR lugar LIKE ? OR autos LIKE ? '
          'OR codigo_fabrica LIKE ? OR notas LIKE ?)');
      args.addAll(List.filled(6, like));
    }
    final filas = await _db.query(
      'compras',
      where: donde.isEmpty ? null : donde.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'fecha_compra DESC, id DESC',
      limit: 2000,
    );
    return filas.map(Compra.deFila).toList();
  }

  /// Todas las compras del período (o todas si es null), de la más vieja a la
  /// más nueva por fecha de compra. Incluye las anuladas (el Excel las marca).
  Future<List<Compra>> comprasDelPeriodo(Periodo? p) async {
    final filas = await _db.query(
      'compras',
      where: p == null ? null : 'fecha_compra >= ? AND fecha_compra < ?',
      whereArgs: p == null ? null : [ms(p.desde), ms(p.hasta)],
      orderBy: 'fecha_compra ASC, id ASC',
    );
    return filas.map(Compra.deFila).toList();
  }

  /// Cantidad de compras activas que todavía tienen 0 impresiones de sticker.
  Future<int> contarSinImprimir() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery("SELECT COUNT(*) FROM compras WHERE estado = 'activa' AND impresiones = 0"),
      ) ??
      0;

  /// Precios pagados antes por el mismo código grabado de fábrica (solo compras activas).
  Future<ReferenciaPrecio?> referenciaCodigoFabrica(String codigoFabrica, {int? excluirId}) async {
    final limpio = codigoFabrica.trim().toUpperCase();
    if (limpio.length < 2) return null;
    final filas = await _db.query(
      'compras',
      columns: ['precio', 'fecha_compra', 'autos'],
      where: "estado = 'activa' AND codigo_fabrica = ?${excluirId != null ? ' AND id != ?' : ''}",
      whereArgs: [limpio, ?excluirId],
      orderBy: 'fecha_compra DESC, id DESC',
    );
    if (filas.isEmpty) return null;
    var suma = 0;
    var min = filas.first['precio']! as int;
    var max = min;
    var autos = '';
    for (final f in filas) {
      final p = f['precio']! as int;
      suma += p;
      if (p < min) min = p;
      if (p > max) max = p;
      if (autos.isEmpty && (f['autos'] as String? ?? '').trim().isNotEmpty) {
        autos = (f['autos']! as String).trim();
      }
    }
    return ReferenciaPrecio(
      codigoFabrica: limpio,
      cantidad: filas.length,
      ultimoPrecio: filas.first['precio']! as int,
      ultimaFecha: deMs(filas.first['fecha_compra']),
      promedio: (suma / filas.length).round(),
      minimo: min,
      maximo: max,
      ultimoAutos: autos,
    );
  }

  /// Sugerencias para autocompletar, las usadas más recientemente primero.
  Future<List<String>> sugerencias(String columna) async {
    const permitidas = {'vendedor', 'lugar', 'autos', 'codigo_fabrica'};
    if (!permitidas.contains(columna)) throw ArgumentError(columna);
    final filas = await _db.rawQuery(
      'SELECT $columna AS v, MAX(fecha_compra) AS m FROM compras '
      "WHERE $columna <> '' GROUP BY $columna ORDER BY m DESC LIMIT 200",
    );
    return filas.map((f) => f['v']! as String).toList();
  }
}
