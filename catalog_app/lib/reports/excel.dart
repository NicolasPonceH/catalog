import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import 'reporte.dart';

// ---------- Estilo de marca ----------

final _azul = ExcelColor.fromHexString('FF0E2A47');
final _naranja = ExcelColor.fromHexString('FFFF7A1A');
final _niebla = ExcelColor.fromHexString('FFF4F6F8');
final _naranjaClaro = ExcelColor.fromHexString('FFFFE9D9');
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
CellStyle _celda(_F f, {bool franja = false, bool anulada = false}) => CellStyle(
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
      bottomBorder: _borde(_azul),
    );

CellStyle _total(_F f) => CellStyle(
      bold: true,
      numberFormat: _numero(f),
      backgroundColorHex: _naranjaClaro,
      horizontalAlign: _alinear(f),
      topBorder: _borde(_naranja, BorderStyle.Medium),
      bottomBorder: _borde(_naranja, BorderStyle.Medium),
    );

final _titulo = CellStyle(bold: true, fontSize: 20, fontColorHex: _azul, verticalAlign: VerticalAlign.Center);
final _marca = CellStyle(bold: true, fontSize: 12, fontColorHex: _naranja);
final _subtitulo = CellStyle(fontSize: 11, fontColorHex: _acero);
final _seccion = CellStyle(bold: true, fontSize: 13, fontColorHex: _azul, bottomBorder: _borde(_naranja, BorderStyle.Medium));
final _kpiEtiqueta = CellStyle(fontSize: 10, fontColorHex: _acero, backgroundColorHex: _niebla, horizontalAlign: HorizontalAlign.Center);
CellStyle _kpiValor(_F f) => CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: _azul,
      numberFormat: _numero(f),
      backgroundColorHex: _niebla,
      horizontalAlign: HorizontalAlign.Center,
      bottomBorder: _borde(_naranja, BorderStyle.Thick),
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

Excel _nuevo(String primeraHoja) {
  final excel = Excel.createExcel();
  final defecto = excel.getDefaultSheet();
  if (defecto != null && defecto != primeraHoja) excel.rename(defecto, primeraHoja);
  return excel;
}

/// Encabezado de marca común: "CataLog" + título + datos del informe.
/// Devuelve la siguiente fila libre.
int _cabecera(Sheet h, String titulo, List<String> lineas, {int columnas = 6}) {
  _escribir(h, 0, [_t('CataLog')], [_marca]);
  _escribir(h, 1, [_t(titulo)], [_titulo]);
  h.merge(_c(0, 1), _c(columnas - 1, 1));
  h.setRowHeight(1, 30);
  var fila = 2;
  for (final l in lineas) {
    _escribir(h, fila, [_t(l)], [_subtitulo]);
    h.merge(_c(0, fila), _c(columnas - 1, fila));
    fila++;
  }
  return fila + 1;
}

/// Tarjetas de cifras grandes (etiqueta arriba, valor abajo), de 2 columnas cada una.
int _tarjetas(Sheet h, int fila, List<(String, CellValue, _F)> datos) {
  for (var k = 0; k < datos.length; k++) {
    final col = k * 2;
    final (etiqueta, valor, f) = datos[k];
    h.updateCell(_c(col, fila), _t(etiqueta), cellStyle: _kpiEtiqueta);
    h.merge(_c(col, fila), _c(col + 1, fila));
    h.updateCell(_c(col, fila + 1), valor, cellStyle: _kpiValor(f));
    h.merge(_c(col, fila + 1), _c(col + 1, fila + 1));
  }
  h.setRowHeight(fila + 1, 34);
  return fila + 3;
}

/// Tabla de grupos (tipo, vendedor o mes) con % del total. Devuelve la siguiente fila libre.
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

CellValue? _mapa(Compra c) => c.lat == null || c.lng == null
    ? null
    : FormulaCellValue('HYPERLINK("https://www.google.com/maps?q=${c.lat},${c.lng}","Ver mapa")');

// ---------- Reporte por período ----------

const _columnasCompras = [
  'Código', 'Fecha de compra', 'Hora', 'Vendedor', 'Lugar', 'Tipo', 'Código de fábrica',
  'Autos', 'Precio', 'Estado', 'Ubicación', 'Notas', 'Anotado el',
];

/// Excel del reporte: Resumen (cifras y tablas) y Compras (detalle).
List<int> excelDeReporte(Reporte r, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Resumen');

  // Resumen
  final res = excel['Resumen'];
  var fila = _cabecera(res, 'Reporte de compras', [
    'Período: ${r.titulo}',
    if (comprador.isNotEmpty) 'Comprador: $comprador',
    'Generado el ${fechaHora(generado ?? DateTime.now())}',
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
  final meses = _porMes(r.compras);
  if (meses.length > 1) fila = _tablaGrupos(res, fila, 'Por mes', 'Mes', meses, r.resumen.total);
  _tablaGrupos(res, fila, 'Por vendedor', 'Vendedor', r.porVendedor, r.resumen.total);
  _anchos(res, [30, 13, 16, 15, 13, 13]);

  // Compras (detalle, con el encabezado fijo al bajar)
  final h = excel['Compras'];
  _escribir(h, 0, [for (final c in _columnasCompras) _t(c)], [for (final _ in _columnasCompras) _encabezado()]);
  h.setRowHeight(0, 30);
  var f = 1;
  for (final c in r.compras) {
    final franja = f.isEven;
    final a = c.anulada;
    _escribir(h, f, [
      _t(c.codigo), _d(c.fechaCompra), _h(c.fechaCompra), _t(c.vendedor), _t(c.lugar), _t(c.tipo),
      _t(c.codigoFabrica), _t(c.autos), _i(c.precio), _t(a ? 'Anulada' : 'Activa'), _mapa(c), _t(c.notas),
      _t(fechaHora(c.creadoEn)),
    ], [
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.fecha, franja: franja, anulada: a),
      _celda(_F.hora, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.dinero, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.enlace, franja: franja),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
    ]);
    f++;
  }
  _escribir(h, f, [_t('TOTAL (${r.resumen.cantidad} activas)'), null, null, null, null, null, null, null, _i(r.resumen.total)],
      [_total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto),
       _total(_F.texto), _total(_F.texto), _total(_F.dinero)]);
  h.freezePanes(rows: 1, columns: 1);
  _anchos(h, [19, 15, 8, 22, 22, 22, 17, 24, 13, 10, 12, 28, 18]);

  excel.setDefaultSheet('Resumen');
  return excel.encode()!;
}

// ---------- Lote escaneado ----------

/// Excel de un lote escaneado: datos del lote, cifras y los catalíticos con su precio.
List<int> excelDeLote(Lote lote, List<ItemLote> items, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Lote');
  final h = excel['Lote'];
  final activos = items.where((i) => !i.compra.anulada).toList();
  final total = activos.fold<int>(0, (s, i) => s + i.compra.precio);
  final recibido = lote.montoRecibido;
  final ganancia = recibido == null ? null : recibido - total;
  final pctMargen = (ganancia != null && total > 0) ? ((ganancia / total) * 100).round() : null;

  var fila = _cabecera(h, lote.nombre, [
    'Creado el ${fechaHora(lote.creadoEn)}${lote.cerradoEn != null ? ' · cerrado el ${fechaHora(lote.cerradoEn!)}' : ''}',
    if (recibido != null)
      'Venta recibida: ${clp(recibido)} · Utilidad neta: ${ganancia! >= 0 ? '+' : ''}${clp(ganancia)}'
          '${pctMargen != null ? ' (${pctMargen >= 0 ? '+' : ''}$pctMargen%)' : ''}',
    if (comprador.isNotEmpty) 'Comprador: $comprador',
    'Generado el ${fechaHora(generado ?? DateTime.now())}',
  ], columnas: 9);
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
  );

  const columnas = ['Código', 'Fecha de compra', 'Hora', 'Vendedor', 'Tipo', 'Código de fábrica', 'Autos', 'Precio', 'Escaneado el'];
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
      _t(c.codigoFabrica), _t(c.autos), _i(c.precio), _t(fechaHora(i.escaneadoEn)),
    ], [
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.fecha, franja: franja, anulada: a),
      _celda(_F.hora, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
      _celda(_F.dinero, franja: franja, anulada: a),
      _celda(_F.texto, franja: franja, anulada: a),
    ]);
    fila++;
    k++;
  }
  _escribir(h, fila, [_t('TOTAL'), null, null, null, null, null, null, _i(total)],
      [_total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto),
       _total(_F.texto), _total(_F.dinero)]);
  if (recibido != null) {
    fila++;
    _escribir(h, fila, [_t('MONTO RECIBIDO'), null, null, null, null, null, null, _i(recibido)],
        [_celda(_F.texto, franja: true), _celda(_F.texto, franja: true), _celda(_F.texto, franja: true),
         _celda(_F.texto, franja: true), _celda(_F.texto, franja: true), _celda(_F.texto, franja: true),
         _celda(_F.texto, franja: true), _celda(_F.dinero, franja: true)]);
    fila++;
    _escribir(h, fila, [_t('UTILIDAD NETA'), null, null, null, null, null, null, _i(ganancia!)],
        [_total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto), _total(_F.texto),
         _total(_F.texto), _total(_F.dinero)]);
  }
  _anchos(h, [19, 15, 8, 22, 22, 17, 24, 13, 18]);
  return excel.encode()!;
}

// ---------- Revisión de Supervisor ----------

/// Un ítem evaluado en la pantalla de Revisión de Supervisor.
class FilaRevisionExcel {
  const FilaRevisionExcel({
    required this.codigo,
    this.compra,
    this.escaneadoEn,
  });

  final String codigo;
  final Compra? compra;
  final DateTime? escaneadoEn;

  bool get verificado => escaneadoEn != null;
}

/// Excel generado desde el Módulo de Revisión del Supervisor: muestra los
/// catalíticos escaneados/verificados, los faltantes y el monto total cuadrado.
List<int> excelDeRevisionSupervisor(
  List<FilaRevisionExcel> filas, {
  String comprador = '',
  String prefijo = '',
  DateTime? generado,
}) {
  final excel = _nuevo('Revisión');
  final h = excel['Revisión'];

  final verificadasActivas = filas.where((f) => f.verificado && f.compra != null && !f.compra!.anulada).toList();
  final totalVerificadas = filas.where((f) => f.verificado).length;
  final pendientesActivas = filas.where((f) => !f.verificado && f.compra != null && !f.compra!.anulada).toList();
  final montoVerificado = verificadasActivas.fold<int>(0, (s, f) => s + f.compra!.precio);
  final montoPendiente = pendientesActivas.fold<int>(0, (s, f) => s + f.compra!.precio);
  final montoCatalogo = montoVerificado + montoPendiente;

  var fila = _cabecera(h, 'Revisión de Supervisor', [
    if (comprador.isNotEmpty || prefijo.isNotEmpty)
      'Comprador: ${comprador.isNotEmpty ? comprador : prefijo}'
          '${comprador.isNotEmpty && prefijo.isNotEmpty ? ' (prefijo $prefijo)' : ''}',
    'Verificados con cámara: $totalVerificadas · Pendientes por escanear: ${pendientesActivas.length}',
    'Generado el ${fechaHora(generado ?? DateTime.now())}',
  ], columnas: 10);

  fila = _tarjetas(h, fila, [
    ('VERIFICADOS', _i(totalVerificadas), _F.entero),
    ('MONTO VERIFICADO', _i(montoVerificado), _F.dinero),
    ('PENDIENTES', _i(pendientesActivas.length), _F.entero),
    ('TOTAL CATÁLOGO', _i(montoCatalogo), _F.dinero),
  ]);

  const columnas = [
    'Estado revisión',
    'Código',
    'Escaneado el',
    'Fecha compra',
    'Vendedor',
    'Tipo',
    'Código fábrica',
    'Autos',
    'Precio',
    'Ubicación',
  ];
  _escribir(h, fila, [for (final c in columnas) _t(c)], [for (final _ in columnas) _encabezado()]);
  h.setRowHeight(fila, 30);
  fila++;

  var k = 0;
  for (final item in filas) {
    final c = item.compra;
    final franja = k.isOdd;
    final anulada = c?.anulada ?? false;
    final estado = anulada
        ? 'Anulada'
        : (item.verificado
            ? (c != null ? 'Verificado ✓' : 'Leído (sin ficha)')
            : 'Pendiente');
    _escribir(h, fila, [
      _t(estado),
      _t(item.codigo),
      _t(item.escaneadoEn != null ? fechaHora(item.escaneadoEn!) : '—'),
      c != null ? _d(c.fechaCompra) : _t('—'),
      _t(c?.vendedor ?? '—'),
      _t(c?.tipo ?? '—'),
      _t(c?.codigoFabrica ?? ''),
      _t(c?.autos ?? ''),
      _i(c?.precio ?? 0),
      c != null ? _mapa(c) : null,
    ], [
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(c != null ? _F.fecha : _F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.texto, franja: franja, anulada: anulada),
      _celda(_F.dinero, franja: franja, anulada: anulada),
      _celda(_F.enlace, franja: franja),
    ]);
    fila++;
    k++;
  }

  _escribir(
    h,
    fila,
    [_t('TOTAL VERIFICADO ($totalVerificadas)'), null, null, null, null, null, null, null, _i(montoVerificado), null],
    [
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.texto),
      _total(_F.dinero),
      _total(_F.texto),
    ],
  );
  _anchos(h, [18, 19, 18, 14, 22, 20, 16, 22, 13, 12]);
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
