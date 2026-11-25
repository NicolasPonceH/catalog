import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../data/supervisor_repo.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import 'reporte.dart';

// ---------- Logo oficial PNG en memoria (síncrono, sin depender de assets async) ----------

final Uint8List _logoPngCache = _generarLogoCatalogPng();

/// Genera un PNG RGBA nítido (192x60) con la insignia oficial de CataLog
/// (fondo azul marino #0E2A47, borde y tubos naranjas #FF7A1A, cuerpo blanco y
/// ranuras de código de barras) para incrustarlo en todos los archivos Excel.
Uint8List _generarLogoCatalogPng() {
  const w = 192;
  const h = 60;
  final raw = BytesBuilder(copy: false);

  double distRRect(double px, double py, double l, double t, double r, double b, double rad) {
    final cx = (l + r) * 0.5;
    final cy = (t + b) * 0.5;
    final hx = (r - l) * 0.5 - rad;
    final hy = (b - t) * 0.5 - rad;
    final dx = (px - cx).abs() - hx;
    final dy = (py - cy).abs() - hy;
    final ox = dx > 0 ? dx : 0.0;
    final oy = dy > 0 ? dy : 0.0;
    final fuera = math.sqrt(ox * ox + oy * oy);
    final dentro = math.min(math.max(dx, dy), 0.0);
    return fuera + dentro - rad;
  }

  double cobertura(double d) => (0.5 - d).clamp(0.0, 1.0);

  const barras = <(double, double)>[
    (22.5, 2.8),
    (27.2, 1.5),
    (30.6, 3.3),
    (35.8, 1.5),
    (39.2, 2.8),
    (43.8, 1.5),
    (47.0, 2.3),
  ];

  for (var y = 0; y < h; y++) {
    raw.addByte(0); // filtro PNG: None
    final py = y + 0.5;
    for (var x = 0; x < w; x++) {
      final px = x + 0.5;
      // Insignia redondeada (4..68, 4..56)
      final dExterior = distRRect(px, py, 3, 3, 71, 57, 14);
      if (dExterior >= 0.5) {
        raw.add(const [0, 0, 0, 0]);
        continue;
      }
      final aExt = cobertura(dExterior);
      final dInterior = distRRect(px, py, 6, 6, 68, 54, 11.5);
      final aInt = cobertura(dInterior);

      // Base: aro naranja (#FF7A1A) y fondo azul marino (#0E2A47)
      var r = 255.0 * (1 - aInt) + 14.0 * aInt;
      var g = 122.0 * (1 - aInt) + 42.0 * aInt;
      var b = 26.0 * (1 - aInt) + 71.0 * aInt;

      // Tubos laterales naranjas (10..64, 26..34)
      final aTubo = cobertura(distRRect(px, py, 10, 26.5, 64, 33.5, 3.2));
      if (aTubo > 0) {
        r = r * (1 - aTubo) + 255.0 * aTubo;
        g = g * (1 - aTubo) + 122.0 * aTubo;
        b = b * (1 - aTubo) + 26.0 * aTubo;
      }

      // Cuerpo blanco del catalítico (17..57, 15..45)
      final aCuerpo = cobertura(distRRect(px, py, 17, 15, 57, 45, 11));
      if (aCuerpo > 0) {
        r = r * (1 - aCuerpo) + 244.0 * aCuerpo;
        g = g * (1 - aCuerpo) + 246.0 * aCuerpo;
        b = b * (1 - aCuerpo) + 248.0 * aCuerpo;
      }

      // Barras verticales azul marino dentro del cuerpo (y: 22..38)
      if (py >= 22 && py <= 38) {
        for (final (bx, bw) in barras) {
          if (px >= bx && px <= bx + bw) {
            r = 14;
            g = 42;
            b = 71;
            break;
          }
        }
      }

      // Línea decorativa naranja a la derecha como acento de marca (78..184, 28..32)
      raw.add([r.round(), g.round(), b.round(), (aExt * 255).round()]);
    }
  }

  final comprimido = zlib.encode(raw.takeBytes());
  final out = BytesBuilder(copy: false);
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void escribirChunk(String tipo, List<int> datos) {
    final len = ByteData(4)..setUint32(0, datos.length);
    out.add(len.buffer.asUint8List());
    final tipoBytes = tipo.codeUnits;
    out.add(tipoBytes);
    out.add(datos);
    final crc = _crc32([...tipoBytes, ...datos]);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    out.add(crcBytes.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // 8-bit
    ..setUint8(9, 6) // RGBA
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  escribirChunk('IHDR', ihdr.buffer.asUint8List());
  escribirChunk('IDAT', comprimido);
  escribirChunk('IEND', const []);
  return out.takeBytes();
}

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ---------- Estilo de marca ----------

final _azul = ExcelColor.fromHexString('FF0E2A47');
final _naranja = ExcelColor.fromHexString('FFFF7A1A');
final _niebla = ExcelColor.fromHexString('FFF4F6F8');
final _naranjaClaro = ExcelColor.fromHexString('FFFFE9D9');
final _verde = ExcelColor.fromHexString('FF1D9E75');
final _verdeClaro = ExcelColor.fromHexString('FFE3F5EE');
final _rojo = ExcelColor.fromHexString('FFB3261E');
final _rojoClaro = ExcelColor.fromHexString('FFFDE8E8');
final _acero = ExcelColor.fromHexString('FF5B6B7C');
final _lineas = ExcelColor.fromHexString('FFDCE3EA');

enum _F { texto, dinero, fecha, hora, entero, porcentaje, enlace }

NumFormat _numero(_F f) => switch (f) {
      _F.dinero => NumFormat.custom(formatCode: r'"$"#,##0'),
      _F.fecha => NumFormat.custom(formatCode: 'dd/mm/yyyy'),
      _F.hora => NumFormat.custom(formatCode: 'hh:mm'),
      _F.entero => NumFormat.custom(formatCode: '#,##0'),
      _F.porcentaje => NumFormat.custom(formatCode: '0%'),
      _F.texto || _F.enlace => NumFormat.standard_0,
    };

Border _borde([ExcelColor? color, BorderStyle estilo = BorderStyle.Thin]) =>
    Border(borderStyle: estilo, borderColorHex: color ?? _lineas);

HorizontalAlign _alinear(_F f) => switch (f) {
      _F.texto || _F.enlace => HorizontalAlign.Left,
      _F.fecha || _F.hora => HorizontalAlign.Center,
      _ => HorizontalAlign.Right,
    };

/// Celda de tabla: franjas alternadas, bordes finos y formato según el tipo.
CellStyle _celda(_F f, {bool franja = false, bool anulada = false, bool alertaRoja = false}) {
  if (alertaRoja) {
    return CellStyle(
      numberFormat: _numero(f),
      backgroundColorHex: _rojoClaro,
      fontColorHex: f == _F.enlace ? _naranja : _rojo,
      bold: f == _F.texto,
      underline: f == _F.enlace ? Underline.Single : Underline.None,
      horizontalAlign: _alinear(f),
      verticalAlign: VerticalAlign.Center,
      leftBorder: _borde(_rojo),
      rightBorder: _borde(_rojo),
      topBorder: _borde(_rojo),
      bottomBorder: _borde(_rojo),
    );
  }
  return CellStyle(
    numberFormat: _numero(f),
    backgroundColorHex: franja ? _niebla : ExcelColor.none,
    fontColorHex: f == _F.enlace ? _naranja : (anulada ? _acero : ExcelColor.black),
    italic: anulada,
    underline: f == _F.enlace ? Underline.Single : Underline.None,
    horizontalAlign: _alinear(f),
    verticalAlign: VerticalAlign.Center,
    leftBorder: _borde(),
    rightBorder: _borde(),
    topBorder: _borde(),
    bottomBorder: _borde(),
  );
}

CellStyle _celdaEstadoRevision({
  required bool verificado,
  required bool conObservacion,
  required bool anulada,
}) {
  if (anulada || conObservacion) {
    return CellStyle(
      bold: true,
      backgroundColorHex: _rojoClaro,
      fontColorHex: _rojo,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      leftBorder: _borde(_rojo),
      rightBorder: _borde(_rojo),
      topBorder: _borde(_rojo),
      bottomBorder: _borde(_rojo),
    );
  }
  if (verificado) {
    return CellStyle(
      bold: true,
      backgroundColorHex: _verdeClaro,
      fontColorHex: _verde,
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      leftBorder: _borde(_verde),
      rightBorder: _borde(_verde),
      topBorder: _borde(_verde),
      bottomBorder: _borde(_verde),
    );
  }
  return CellStyle(
    bold: true,
    backgroundColorHex: _naranjaClaro,
    fontColorHex: _azul,
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    leftBorder: _borde(_naranja),
    rightBorder: _borde(_naranja),
    topBorder: _borde(_naranja),
    bottomBorder: _borde(_naranja),
  );
}

CellStyle _encabezado([HorizontalAlign alinear = HorizontalAlign.Center]) => CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: _azul,
      horizontalAlign: alinear,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: _borde(_azul),
      rightBorder: _borde(_azul),
      topBorder: _borde(_azul),
      bottomBorder: _borde(_naranja, BorderStyle.Medium),
    );

CellStyle _total(_F f) => CellStyle(
      bold: true,
      numberFormat: _numero(f),
      backgroundColorHex: _naranjaClaro,
      horizontalAlign: _alinear(f),
      topBorder: _borde(_naranja, BorderStyle.Medium),
      bottomBorder: _borde(_naranja, BorderStyle.Medium),
    );

final _bannerMarca = CellStyle(
  bold: true,
  fontSize: 15,
  fontColorHex: ExcelColor.white,
  backgroundColorHex: _azul,
  verticalAlign: VerticalAlign.Center,
  bottomBorder: _borde(_naranja, BorderStyle.Medium),
);
final _bannerSello = CellStyle(
  bold: true,
  fontSize: 10,
  fontColorHex: _naranja,
  backgroundColorHex: _azul,
  horizontalAlign: HorizontalAlign.Right,
  verticalAlign: VerticalAlign.Center,
  bottomBorder: _borde(_naranja, BorderStyle.Medium),
);
final _titulo = CellStyle(bold: true, fontSize: 20, fontColorHex: _azul, verticalAlign: VerticalAlign.Center);
final _subtitulo = CellStyle(fontSize: 11, fontColorHex: _acero, verticalAlign: VerticalAlign.Center);
final _pieMarca = CellStyle(italic: true, fontSize: 10, fontColorHex: _acero);
final _seccion = CellStyle(bold: true, fontSize: 13, fontColorHex: _azul, bottomBorder: _borde(_naranja, BorderStyle.Medium));
final _kpiEtiqueta = CellStyle(
  bold: true,
  fontSize: 10,
  fontColorHex: _acero,
  backgroundColorHex: _niebla,
  horizontalAlign: HorizontalAlign.Center,
  topBorder: _borde(),
  leftBorder: _borde(),
  rightBorder: _borde(),
);
CellStyle _kpiValor(_F f, {bool alerta = false}) => CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: alerta ? _rojo : _azul,
      numberFormat: _numero(f),
      backgroundColorHex: alerta ? _rojoClaro : _niebla,
      horizontalAlign: HorizontalAlign.Center,
      leftBorder: _borde(alerta ? _rojo : _lineas),
      rightBorder: _borde(alerta ? _rojo : _lineas),
      bottomBorder: _borde(alerta ? _rojo : _naranja, BorderStyle.Thick),
    );

// ---------- Ayudas ----------

TextCellValue _t(String s) => TextCellValue(s);
IntCellValue _i(int n) => IntCellValue(n);
DateCellValue _d(DateTime f) => DateCellValue(year: f.year, month: f.month, day: f.day);
TimeCellValue _h(DateTime f) => TimeCellValue(hour: f.hour, minute: f.minute);

CellIndex _c(int col, int fila) => CellIndex.indexByColumnRow(columnIndex: col, rowIndex: fila);

/// Escribe valores en la fila [fila] desde la columna [desde].
void _escribir(Sheet h, int fila, List<CellValue?> valores, List<CellStyle?> estilos, {int desde = 0}) {
  for (var i = 0; i < valores.length; i++) {
    h.updateCell(_c(desde + i, fila), valores[i], cellStyle: i < estilos.length ? estilos[i] : null);
  }
}

void _anchos(Sheet h, List<double> anchos) {
  for (var i = 0; i < anchos.length; i++) {
    h.setColumnWidth(i, anchos[i]);
  }
}

void _prepararPagina(Sheet h, {ExcelColor? colorPestana}) {
  if (colorPestana != null) h.tabColor = colorPestana;
  h.pageSetup = const PageSetup(
    orientation: PageOrientation.landscape,
    fitToWidth: 1,
    fitToHeight: 0,
  );
}

Excel _nuevo(String primeraHoja) {
  final excel = Excel.createExcel();
  final defecto = excel.getDefaultSheet();
  if (defecto != null && defecto != primeraHoja) excel.rename(defecto, primeraHoja);
  return excel;
}

/// Encabezado corporativo con cintillo azul marino, logo oficial de CataLog incrustado
/// y sello "Generado por CataLog". Devuelve la siguiente fila libre.
int _cabecera(Sheet h, String titulo, List<String> lineas, {int columnas = 6}) {
  final ult = math.max(columnas - 1, 3);
  for (var c = 0; c <= ult; c++) {
    h.updateCell(
      _c(c, 0),
      c == 0
          ? _t('          CataLog · Control de Catalíticos')
          : (c == ult ? _t('Generado por CataLog') : null),
      cellStyle: c == ult ? _bannerSello : _bannerMarca,
    );
  }
  if (ult >= 2) {
    h.merge(_c(0, 0), _c(ult - 1, 0));
  }
  h.setRowHeight(0, 36);
  try {
    h.insertImage(_logoPngCache, anchor: _c(0, 0), width: 128, height: 40);
  } catch (_) {}

  _escribir(h, 1, [_t(titulo)], [_titulo]);
  h.merge(_c(0, 1), _c(ult, 1));
  h.setRowHeight(1, 30);
  var fila = 2;
  for (final l in lineas) {
    _escribir(h, fila, [_t(l)], [_subtitulo]);
    h.merge(_c(0, fila), _c(ult, fila));
    fila++;
  }
  return fila + 1;
}

void _pieGeneradoPor(Sheet h, int fila, {int columnas = 6}) {
  final ult = math.max(columnas - 1, 3);
  _escribir(
    h,
    fila,
    [_t('Generado por CataLog · Registro y auditoría de catalíticos sin internet')],
    [_pieMarca],
  );
  h.merge(_c(0, fila), _c(ult, fila));
}

/// Tarjetas de cifras grandes (etiqueta arriba, valor abajo), de 2 columnas cada una.
int _tarjetas(Sheet h, int fila, List<(String, CellValue, _F)> datos, {Set<int> indicesAlerta = const {}}) {
  for (var k = 0; k < datos.length; k++) {
    final col = k * 2;
    final (etiqueta, valor, f) = datos[k];
    final alerta = indicesAlerta.contains(k);
    h.updateCell(_c(col, fila), _t(etiqueta), cellStyle: _kpiEtiqueta);
    h.merge(_c(col, fila), _c(col + 1, fila));
    h.updateCell(_c(col, fila + 1), valor, cellStyle: _kpiValor(f, alerta: alerta));
    h.merge(_c(col, fila + 1), _c(col + 1, fila + 1));
  }
  h.setRowHeight(fila + 1, 34);
  return fila + 3;
}

/// Tabla de grupos (tipo, vendedor, llenado o mes) con % del total. Devuelve la siguiente fila libre.
int _tablaGrupos(Sheet h, int fila, String titulo, String columna, List<FilaGrupo> filas, int total) {
  _escribir(h, fila, [_t(titulo)], [_seccion]);
  h.merge(_c(0, fila), _c(4, fila));
  fila++;
  _escribir(h, fila, [_t(columna), _t('Cantidad'), _t('Total pagado'), _t('Promedio'), _t('% del total')],
      [_encabezado(HorizontalAlign.Left), _encabezado(), _encabezado(), _encabezado(), _encabezado()]);
  fila++;
  for (var k = 0; k < filas.length; k++) {
    final g = filas[k];
    final franja = k.isOdd;
    _escribir(h, fila, [
      _t(g.nombre),
      _i(g.cantidad),
      _i(g.total),
      _i(g.promedio),
      DoubleCellValue(total == 0 ? 0 : g.total / total),
    ], [
      _celda(_F.texto, franja: franja),
      _celda(_F.entero, franja: franja),
      _celda(_F.dinero, franja: franja),
      _celda(_F.dinero, franja: franja),
      _celda(_F.porcentaje, franja: franja),
    ]);
    fila++;
  }
  final cantidad = filas.fold<int>(0, (s, g) => s + g.cantidad);
  _escribir(h, fila, [_t('Total'), _i(cantidad), _i(total), null, DoubleCellValue(total == 0 ? 0 : 1)],
      [_total(_F.texto), _total(_F.entero), _total(_F.dinero), _total(_F.dinero), _total(_F.porcentaje)]);
  return fila + 2;
}

String _mes(DateTime f) {
  const nombres = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
      'septiembre', 'octubre', 'noviembre', 'diciembre'];
  return '${capitalizar(nombres[f.month - 1])} ${f.year}';
}

List<FilaGrupo> _porMes(List<Compra> compras) {
  final cantidad = <int, int>{};
  final total = <int, int>{};
  for (final c in compras.where((c) => !c.anulada)) {
    final k = c.fechaCompra.year * 100 + c.fechaCompra.month;
    cantidad[k] = (cantidad[k] ?? 0) + 1;
    total[k] = (total[k] ?? 0) + c.precio;
  }
  final claves = cantidad.keys.toList()..sort();
  return [for (final k in claves) FilaGrupo(_mes(DateTime(k ~/ 100, k % 100)), cantidad[k]!, total[k]!)];
}

List<FilaGrupo> _porLlenado(List<Compra> compras) {
  final cantidad = <NivelLlenado, int>{};
  final total = <NivelLlenado, int>{};
  for (final c in compras.where((c) => !c.anulada)) {
    cantidad[c.llenado] = (cantidad[c.llenado] ?? 0) + 1;
    total[c.llenado] = (total[c.llenado] ?? 0) + c.precio;
  }
  final lista = [
    for (final niv in NivelLlenado.values)
      if ((cantidad[niv] ?? 0) > 0) FilaGrupo(niv.etiqueta, cantidad[niv]!, total[niv]!),
  ]..sort((a, b) => b.total.compareTo(a.total));
  return lista;
}

CellValue? _mapa(Compra c) => c.lat == null || c.lng == null
    ? null
    : FormulaCellValue('HYPERLINK("https://www.google.com/maps?q=${c.lat},${c.lng}","Ver mapa")');

// ---------- Reporte por período ----------

const _columnasCompras = [
  'Código', 'Fecha de compra', 'Hora', 'Vendedor', 'Lugar', 'Tipo', 'Código de fábrica',
  'Autos', 'Precio', 'Estado', 'Ubicación', 'Notas', 'Anotado el', 'Llenado', 'Monto activo',
];

/// Excel del reporte: Resumen (con logo y KPIs), Compras (con ExcelTable y filtros)
/// y Tabla Dinámica (con PivotTables nativas de Excel).
List<int> excelDeReporte(Reporte r, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Resumen');
  final ahora = generado ?? DateTime.now();

  // 1. Hoja Resumen
  final res = excel['Resumen'];
  _prepararPagina(res, colorPestana: _azul);
  var fila = _cabecera(res, 'Reporte de compras', [
    'Período: ${r.titulo}',
    if (comprador.isNotEmpty) 'Comprador: $comprador',
    'Generado el ${fechaHora(ahora)} · CataLog',
  ]);
  fila = _tarjetas(res, fila, [
    ('TOTAL GASTADO', _i(r.resumen.total), _F.dinero),
    ('CATALÍTICOS', _i(r.resumen.cantidad), _F.entero),
    ('PROMEDIO', _i(r.resumen.promedio), _F.dinero),
  ]);
  if (r.anuladas > 0) {
    _escribir(res, fila - 1, [_t('${r.anuladas} compras anuladas no se suman en los totales.')], [_subtitulo]);
    res.merge(_c(0, fila - 1), _c(5, fila - 1));
    fila++;
  }
  fila = _tablaGrupos(res, fila, 'Por tipo de catalítico', 'Tipo', r.porTipo, r.resumen.total);
  final llenados = _porLlenado(r.compras);
  if (llenados.isNotEmpty) {
    fila = _tablaGrupos(res, fila, 'Por llenado de cerámica', 'Llenado', llenados, r.resumen.total);
  }
  final meses = _porMes(r.compras);
  if (meses.length > 1) fila = _tablaGrupos(res, fila, 'Por mes', 'Mes', meses, r.resumen.total);
  fila = _tablaGrupos(res, fila, 'Por vendedor', 'Vendedor', r.porVendedor, r.resumen.total);
  _pieGeneradoPor(res, fila);
  _anchos(res, [30, 14, 17, 16, 14, 14]);

  // 2. Hoja Compras (detalle con encabezado fijo y tabla filtrable de Excel)
  final h = excel['Compras'];
  _prepararPagina(h, colorPestana: _verde);
  _escribir(h, 0, [for (final c in _columnasCompras) _t(c)], [for (final _ in _columnasCompras) _encabezado()]);
  h.setRowHeight(0, 30);
  var f = 1;
  for (final c in r.compras) {
    final franja = f.isEven;
    final a = c.anulada;
    _escribir(h, f, [
      _t(c.codigo), _d(c.fechaCompra), _h(c.fechaCompra), _t(c.vendedor), _t(c.lugar), _t(c.tipo),
      _t(c.codigoFabrica), _t(c.autos), _i(c.precio), _t(a ? 'Anulada' : 'Activa'), _mapa(c), _t(c.notas),
      _t(fechaHora(c.creadoEn)), _t(c.llenado.etiqueta), _i(a ? 0 : c.precio),
    ], [
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.fecha, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.hora, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.dinero, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.enlace, franja: franja),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: c.llenado == NivelLlenado.fundido),
      _celda(_F.dinero, franja: franja, anulada: a),
    ]);
    f++;
  }
  _escribir(
    h,
    f,
    [
      _t('TOTAL (${r.resumen.cantidad} activas)'),
      null, null, null, null, null, null, null,
      _i(r.resumen.total),
      null, null, null, null, null,
      _i(r.resumen.total),
    ],
    [for (var col = 0; col < _columnasCompras.length; col++) _total(col == 8 || col == 14 ? _F.dinero : _F.texto)],
  );
  if (r.compras.isNotEmpty) {
    h.addTable(ExcelTable(
      name: 'TablaCompras',
      from: _c(0, 0),
      to: _c(_columnasCompras.length - 1, f - 1),
      style: TableStyle.medium2,
      showRowStripes: true,
    ));
  }
  h.freezePanes(rows: 1, columns: 1);
  _anchos(h, [19, 15, 8, 22, 20, 22, 17, 22, 13, 11, 12, 26, 18, 16, 14]);

  // 3. Hoja Tabla Dinámica (PivotTables nativas sobre Compras)
  if (r.compras.isNotEmpty) {
    final din = excel['Tabla Dinámica'];
    _prepararPagina(din, colorPestana: _naranja);
    final filaIni = _cabecera(din, 'Tablas Dinámicas · ${r.titulo}', [
      'Tablas dinámicas interactivas generadas desde la hoja Compras (se actualizan solas al abrir en Excel).',
      'Filtra o despliega por Vendedor, Tipo, Estado o Nivel de llenado.',
    ], columnas: 9);
    din.addPivotTable(PivotTable(
      name: 'DinamicaVendedor',
      anchor: _c(0, filaIni + 1),
      sourceSheet: 'Compras',
      sourceFrom: _c(0, 0),
      sourceTo: _c(_columnasCompras.length - 1, f - 1),
      rowField: 3, // Vendedor
      subRowFields: const [5], // Tipo
      pageFields: const [9], // Estado (Activa / Anulada)
      dataFields: const [
        PivotDataField(0, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(14, function: PivotFunction.sum, name: 'Total Activo CLP'),
      ],
    ));
    din.addPivotTable(PivotTable(
      name: 'DinamicaTipoLlenado',
      anchor: _c(5, filaIni + 1),
      sourceSheet: 'Compras',
      sourceFrom: _c(0, 0),
      sourceTo: _c(_columnasCompras.length - 1, f - 1),
      rowField: 5, // Tipo
      subRowFields: const [13], // Llenado
      pageFields: const [9],
      dataFields: const [
        PivotDataField(0, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(14, function: PivotFunction.sum, name: 'Total Activo CLP'),
      ],
    ));
    _anchos(din, [28, 14, 18, 6, 6, 28, 14, 18, 14]);
  }

  excel.setDefaultSheet('Resumen');
  return excel.encode()!;
}

// ---------- Lote escaneado ----------

/// Excel de un lote escaneado: logo CataLog, KPIs de utilidad, tabla filtrable y hoja de Tabla Dinámica.
List<int> excelDeLote(Lote lote, List<ItemLote> items, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Lote');
  final h = excel['Lote'];
  _prepararPagina(h, colorPestana: _azul);
  final activos = items.where((i) => !i.compra.anulada).toList();
  final total = activos.fold<int>(0, (s, i) => s + i.compra.precio);
  final recibido = lote.montoRecibido;
  final ganancia = recibido == null ? null : recibido - total;
  final pctMargen = (ganancia != null && total > 0) ? ((ganancia / total) * 100).round() : null;

  const columnas = [
    'Código', 'Fecha de compra', 'Hora', 'Vendedor', 'Tipo', 'Código de fábrica',
    'Autos', 'Precio', 'Escaneado el', 'Llenado',
  ];

  var fila = _cabecera(h, lote.nombre, [
    'Creado el ${fechaHora(lote.creadoEn)}${lote.cerradoEn != null ? ' · cerrado el ${fechaHora(lote.cerradoEn!)}' : ''}',
    if (recibido != null)
      'Venta recibida: ${clp(recibido)} · Utilidad neta: ${ganancia! >= 0 ? '+' : ''}${clp(ganancia)}'
          '${pctMargen != null ? ' (${pctMargen >= 0 ? '+' : ''}$pctMargen%)' : ''}',
    if (comprador.isNotEmpty) 'Comprador: $comprador',
    'Generado el ${fechaHora(generado ?? DateTime.now())} · CataLog',
  ], columnas: columnas.length);
  fila = _tarjetas(
    h,
    fila,
    recibido == null
        ? [
            ('TOTAL PAGADO', _i(total), _F.dinero),
            ('CATALÍTICOS', _i(activos.length), _F.entero),
            ('PROMEDIO', _i(activos.isEmpty ? 0 : (total / activos.length).round()), _F.dinero),
          ]
        : [
            ('COSTO PAGADO', _i(total), _F.dinero),
            ('MONTO RECIBIDO', _i(recibido), _F.dinero),
            ('UTILIDAD NETA', _i(ganancia!), _F.dinero),
            ('CATALÍTICOS', _i(activos.length), _F.entero),
          ],
    indicesAlerta: ganancia != null && ganancia < 0 ? const {2} : const {},
  );

  final filaEnc = fila;
  _escribir(h, fila, [for (final c in columnas) _t(c)], [for (final _ in columnas) _encabezado()]);
  h.setRowHeight(fila, 30);
  fila++;
  var k = 0;
  for (final i in items.reversed) {
    final c = i.compra;
    final franja = k.isOdd;
    final a = c.anulada;
    _escribir(h, fila, [
      _t(c.codigo), _d(c.fechaCompra), _h(c.fechaCompra), _t(c.vendedor), _t(a ? '${c.tipo} (anulada)' : c.tipo),
      _t(c.codigoFabrica), _t(c.autos), _i(c.precio), _t(fechaHora(i.escaneadoEn)), _t(c.llenado.etiqueta),
    ], [
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.fecha, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.hora, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.dinero, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: a),
      _celda(_F.texto, franja: franja, anulada: a, alertaRoja: c.llenado == NivelLlenado.fundido),
    ]);
    fila++;
    k++;
  }
  final filaFinDatos = fila - 1;

  _escribir(h, fila, [_t('TOTAL'), null, null, null, null, null, null, _i(total), null, null],
      [for (var col = 0; col < columnas.length; col++) _total(col == 7 ? _F.dinero : _F.texto)]);
  if (recibido != null) {
    fila++;
    _escribir(h, fila, [_t('MONTO RECIBIDO'), null, null, null, null, null, null, _i(recibido), null, null],
        [for (var col = 0; col < columnas.length; col++) _celda(col == 7 ? _F.dinero : _F.texto, franja: true)]);
    fila++;
    _escribir(h, fila, [_t('UTILIDAD NETA'), null, null, null, null, null, null, _i(ganancia!), null, null],
        [for (var col = 0; col < columnas.length; col++) _total(col == 7 ? _F.dinero : _F.texto)]);
  }

  if (items.isNotEmpty) {
    h.addTable(ExcelTable(
      name: 'TablaLote',
      from: _c(0, filaEnc),
      to: _c(columnas.length - 1, filaFinDatos),
      style: TableStyle.medium2,
      showRowStripes: true,
    ));
    final din = excel['Tabla Dinámica'];
    _prepararPagina(din, colorPestana: _naranja);
    final fDin = _cabecera(din, 'Tabla Dinámica · ${lote.nombre}', [
      'Agrupación automática del lote por Tipo de catalítico, Llenado y Vendedor.',
    ], columnas: 9);
    din.addPivotTable(PivotTable(
      name: 'LotePorTipo',
      anchor: _c(0, fDin + 1),
      sourceSheet: 'Lote',
      sourceFrom: _c(0, filaEnc),
      sourceTo: _c(columnas.length - 1, filaFinDatos),
      rowField: 4, // Tipo
      subRowFields: const [9], // Llenado
      dataFields: const [
        PivotDataField(0, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(7, function: PivotFunction.sum, name: 'Costo Pagado CLP'),
      ],
    ));
    din.addPivotTable(PivotTable(
      name: 'LotePorVendedor',
      anchor: _c(5, fDin + 1),
      sourceSheet: 'Lote',
      sourceFrom: _c(0, filaEnc),
      sourceTo: _c(columnas.length - 1, filaFinDatos),
      rowField: 3, // Vendedor
      dataFields: const [
        PivotDataField(0, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(7, function: PivotFunction.sum, name: 'Costo Pagado CLP'),
      ],
    ));
    _anchos(din, [28, 14, 18, 6, 6, 26, 14, 18, 14]);
  }

  _anchos(h, [19, 15, 8, 22, 22, 17, 24, 13, 18, 16]);
  excel.setDefaultSheet('Lote');
  return excel.encode()!;
}

// ---------- Revisión de Supervisor ----------

/// Un ítem evaluado en la pantalla de Revisión de Supervisor o en un Lote de Supervisor.
class FilaRevisionExcel {
  const FilaRevisionExcel({
    required this.codigo,
    this.compra,
    this.escaneadoEn,
    this.observacion = ObservacionSupervisor.vacia,
    this.vendedorRespaldo = '',
    this.tipoRespaldo = '',
    this.llenadoRespaldo,
    this.codigoFabricaRespaldo = '',
    this.autosRespaldo = '',
    this.precioRespaldo = 0,
    this.fechaCompraRespaldo,
  });

  factory FilaRevisionExcel.deItemLoteSupervisor(ItemLoteSupervisor it) => FilaRevisionExcel(
        codigo: it.codigo,
        escaneadoEn: it.escaneadoEn,
        observacion: it.observacion,
        vendedorRespaldo: it.vendedor,
        tipoRespaldo: it.tipo,
        llenadoRespaldo: it.llenado,
        codigoFabricaRespaldo: it.codigoFabrica,
        autosRespaldo: it.autos,
        precioRespaldo: it.precio,
        fechaCompraRespaldo: it.fechaCompra,
      );

  final String codigo;
  final Compra? compra;
  final DateTime? escaneadoEn;
  final ObservacionSupervisor observacion;

  // Campos de respaldo cuando proviene de un Lote de Supervisor ya guardado.
  final String vendedorRespaldo;
  final String tipoRespaldo;
  final NivelLlenado? llenadoRespaldo;
  final String codigoFabricaRespaldo;
  final String autosRespaldo;
  final int precioRespaldo;
  final DateTime? fechaCompraRespaldo;

  bool get verificado => escaneadoEn != null;
  bool get anulada => compra?.anulada ?? false;
  int get precioEfectivo => compra != null ? (compra!.anulada ? 0 : compra!.precio) : precioRespaldo;
  DateTime? get fechaEfectiva => compra?.fechaCompra ?? fechaCompraRespaldo;
  String get vendedorEfectivo => compra?.vendedor ?? (vendedorRespaldo.isEmpty ? '—' : vendedorRespaldo);
  String get tipoEfectivo => compra?.tipo ?? (tipoRespaldo.isEmpty ? '—' : tipoRespaldo);
  NivelLlenado get llenadoEfectivo => compra?.llenado ?? llenadoRespaldo ?? NivelLlenado.entero;
  String get codigoFabricaEfectivo => compra?.codigoFabrica ?? codigoFabricaRespaldo;
  String get autosEfectivo => compra?.autos ?? autosRespaldo;
}

/// Excel profesional del Módulo de Revisión del Supervisor:
/// - Logo oficial CataLog y KPIs ejecutivos (incluyendo alerta roja si hay observaciones).
/// - Filas con observación / discrepancia o anuladas destacadas en rojo.
/// - Tabla nativa filtrable (`ExcelTable`) y hoja `Tabla Dinámica` con `PivotTable`s reales.
List<int> excelDeRevisionSupervisor(
  List<FilaRevisionExcel> filas, {
  String titulo = 'Revisión de Supervisor',
  String comprador = '',
  String prefijo = '',
  String rangoFechas = '',
  DateTime? generado,
}) {
  final excel = _nuevo('Revisión');
  final h = excel['Revisión'];
  _prepararPagina(h, colorPestana: _azul);

  final totalVerificadas = filas.where((f) => f.verificado && !f.anulada).length;
  final conObs = filas.where((f) => f.observacion.activa).length;
  final pendientes = filas.where((f) => !f.verificado && !f.anulada).toList();
  final montoVerificado = filas.where((f) => f.verificado && !f.anulada).fold<int>(0, (s, f) => s + f.precioEfectivo);
  final montoPendiente = pendientes.fold<int>(0, (s, f) => s + f.precioEfectivo);
  final montoCatalogo = montoVerificado + montoPendiente;

  const columnas = [
    'Estado revisión',
    'Observación / Discrepancia',
    'Código',
    'Escaneado el',
    'Fecha compra',
    'Vendedor',
    'Tipo',
    'Llenado',
    'Código fábrica',
    'Autos',
    'Precio',
    'Monto verificado',
    'Ubicación',
  ];

  var fila = _cabecera(h, titulo, [
    if (comprador.isNotEmpty || prefijo.isNotEmpty)
      'Comprador: ${comprador.isNotEmpty ? comprador : prefijo}'
          '${comprador.isNotEmpty && prefijo.isNotEmpty ? ' (prefijo $prefijo)' : ''}'
          '${rangoFechas.isNotEmpty ? ' · Fechas: $rangoFechas' : ''}',
    'Verificados: $totalVerificadas · Pendientes: ${pendientes.length} · Con observación: $conObs',
    'Generado el ${fechaHora(generado ?? DateTime.now())} · CataLog',
  ], columnas: columnas.length);

  fila = _tarjetas(
    h,
    fila,
    [
      ('VERIFICADOS', _i(totalVerificadas), _F.entero),
      ('MONTO VERIFICADO', _i(montoVerificado), _F.dinero),
      ('CON OBSERVACIÓN', _i(conObs), _F.entero),
      ('PENDIENTES', _i(pendientes.length), _F.entero),
      ('TOTAL CATÁLOGO', _i(montoCatalogo), _F.dinero),
    ],
    indicesAlerta: {if (conObs > 0) 2},
  );

  final filaEnc = fila;
  _escribir(h, fila, [for (final c in columnas) _t(c)], [for (final _ in columnas) _encabezado()]);
  h.setRowHeight(fila, 30);
  fila++;

  var k = 0;
  for (final item in filas) {
    final c = item.compra;
    final franja = k.isOdd;
    final anulada = item.anulada;
    final obsActiva = item.observacion.activa;
    final roja = anulada || obsActiva;
    final estado = anulada
        ? 'Anulada'
        : (obsActiva
            ? 'Con observación'
            : (item.verificado
                ? (c != null || item.precioRespaldo > 0 ? 'Verificado' : 'Leído (sin ficha)')
                : 'Pendiente'));
    final fCompra = item.fechaEfectiva;
    final precio = c?.precio ?? item.precioRespaldo;
    final verifMonto = (item.verificado && !anulada) ? item.precioEfectivo : 0;

    _escribir(h, fila, [
      _t(estado),
      _t(obsActiva ? item.observacion.resumen : '—'),
      _t(item.codigo),
      _t(item.escaneadoEn != null ? fechaHora(item.escaneadoEn!) : '—'),
      fCompra != null ? _d(fCompra) : _t('—'),
      _t(item.vendedorEfectivo),
      _t(item.tipoEfectivo),
      _t(item.llenadoEfectivo.etiqueta),
      _t(item.codigoFabricaEfectivo),
      _t(item.autosEfectivo),
      _i(precio),
      _i(verifMonto),
      c != null ? _mapa(c) : null,
    ], [
      _celdaEstadoRevision(verificado: item.verificado, conObservacion: obsActiva, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(fCompra != null ? _F.fecha : _F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja || item.llenadoEfectivo == NivelLlenado.fundido),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.texto, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.dinero, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.dinero, franja: franja, anulada: anulada, alertaRoja: roja),
      _celda(_F.enlace, franja: franja),
    ]);
    fila++;
    k++;
  }
  final filaFinDatos = fila - 1;

  _escribir(
    h,
    fila,
    [
      _t('TOTAL VERIFICADO ($totalVerificadas)'),
      _t(conObs > 0 ? '$conObs con observación' : ''),
      null, null, null, null, null, null, null, null,
      _i(montoCatalogo),
      _i(montoVerificado),
      null,
    ],
    [for (var col = 0; col < columnas.length; col++) _total(col == 10 || col == 11 ? _F.dinero : _F.texto)],
  );
  _pieGeneradoPor(h, fila + 2, columnas: columnas.length);
  h.freezePanes(rows: filaEnc + 1, columns: 3);
  _anchos(h, [17, 28, 19, 18, 14, 22, 20, 16, 16, 22, 13, 15, 12]);

  if (filas.isNotEmpty) {
    h.addTable(ExcelTable(
      name: 'TablaRevision',
      from: _c(0, filaEnc),
      to: _c(columnas.length - 1, filaFinDatos),
      style: TableStyle.medium2,
      showRowStripes: true,
    ));

    final din = excel['Tabla Dinámica'];
    _prepararPagina(din, colorPestana: _naranja);
    final fDin = _cabecera(din, 'Tablas Dinámicas · $titulo', [
      'Cuadratura dinámica por Estado de revisión, Vendedor, Tipo y Nivel de llenado.',
      if (conObs > 0) 'Atención: hay $conObs catalítico(s) marcados con observación en rojo en la hoja Revisión.',
    ], columnas: 9);

    din.addPivotTable(PivotTable(
      name: 'RevisionPorEstado',
      anchor: _c(0, fDin + 1),
      sourceSheet: 'Revisión',
      sourceFrom: _c(0, filaEnc),
      sourceTo: _c(columnas.length - 1, filaFinDatos),
      rowField: 0, // Estado revisión
      subRowFields: const [6], // Tipo
      dataFields: const [
        PivotDataField(2, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(10, function: PivotFunction.sum, name: 'Precio Catálogo CLP'),
        PivotDataField(11, function: PivotFunction.sum, name: 'Monto Verificado CLP'),
      ],
    ));

    din.addPivotTable(PivotTable(
      name: 'RevisionPorVendedor',
      anchor: _c(5, fDin + 1),
      sourceSheet: 'Revisión',
      sourceFrom: _c(0, filaEnc),
      sourceTo: _c(columnas.length - 1, filaFinDatos),
      rowField: 5, // Vendedor
      subRowFields: const [7], // Llenado
      pageFields: const [0], // Estado revisión
      dataFields: const [
        PivotDataField(2, function: PivotFunction.count, name: 'Piezas'),
        PivotDataField(11, function: PivotFunction.sum, name: 'Monto Verificado CLP'),
      ],
    ));
    _anchos(din, [26, 13, 18, 18, 5, 26, 13, 18, 14]);
  }

  excel.setDefaultSheet('Revisión');
  return excel.encode()!;
}

/// Guarda el archivo en la carpeta temporal y abre el menú para compartirlo
/// (WhatsApp, correo, Drive…).
Future<void> compartirExcel(List<int> bytes, String nombreArchivo, {String? texto}) async {
  final dir = await getTemporaryDirectory();
  final limpio = nombreArchivo.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  final archivo = File(p.join(dir.path, limpio));
  await archivo.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile(archivo.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    ],
    text: texto,
  ));
}
