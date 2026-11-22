import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/compra.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import 'reporte.dart';

final _dinero = CellStyle(numberFormat: NumFormat.custom(formatCode: r'"$"#,##0'));
final _dineroNegrita = CellStyle(numberFormat: NumFormat.custom(formatCode: r'"$"#,##0'), bold: true);
final _fecha = CellStyle(numberFormat: NumFormat.custom(formatCode: 'dd/mm/yyyy'));
final _hora = CellStyle(numberFormat: NumFormat.custom(formatCode: 'hh:mm'));
final _negrita = CellStyle(bold: true);
final _titulo = CellStyle(bold: true, fontSize: 14);
final _encabezado = CellStyle(
  bold: true,
  fontColorHex: ExcelColor.white,
  backgroundColorHex: ExcelColor.fromHexString('FF0E2A47'),
);

/// Escribe una fila al final de la hoja, con estilos por columna.
void _fila(Sheet hoja, List<CellValue?> valores, {Map<int, CellStyle> estilos = const {}, CellStyle? todo}) {
  final r = hoja.maxRows;
  for (var c = 0; c < valores.length; c++) {
    hoja.updateCell(
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      valores[c],
      cellStyle: estilos[c] ?? todo,
    );
  }
}

TextCellValue _t(String s) => TextCellValue(s);
IntCellValue _i(int n) => IntCellValue(n);
DateCellValue _d(DateTime f) => DateCellValue(year: f.year, month: f.month, day: f.day);
TimeCellValue _h(DateTime f) => TimeCellValue(hour: f.hour, minute: f.minute);

void _anchos(Sheet hoja, List<double> anchos) {
  for (var i = 0; i < anchos.length; i++) {
    hoja.setColumnWidth(i, anchos[i]);
  }
}

Excel _nuevo(String primeraHoja) {
  final excel = Excel.createExcel();
  final defecto = excel.getDefaultSheet();
  if (defecto != null && defecto != primeraHoja) excel.rename(defecto, primeraHoja);
  return excel;
}

const _columnasCompras = [
  'Código', 'Fecha de compra', 'Hora', 'Vendedor', 'Lugar', 'Precio', 'Motor', 'Material',
  'Original', 'Código de fábrica', 'Autos', 'Latitud', 'Longitud', 'Notas', 'Estado', 'Anotado el',
];

void _filaCompra(Sheet hoja, Compra c) {
  _fila(hoja, [
    _t(c.codigo),
    _d(c.fechaCompra),
    _h(c.fechaCompra),
    _t(c.vendedor),
    _t(c.lugar),
    _i(c.precio),
    _t(c.motor.etiqueta),
    _t(c.material.etiqueta),
    _t(c.original ? 'Sí' : 'No'),
    _t(c.codigoFabrica),
    _t(c.autos),
    c.lat == null ? null : DoubleCellValue(c.lat!),
    c.lng == null ? null : DoubleCellValue(c.lng!),
    _t(c.notas),
    _t(c.anulada ? 'Anulada' : 'Activa'),
    _t(fechaHora(c.creadoEn)),
  ], estilos: {1: _fecha, 2: _hora, 5: _dinero});
}

void _hojaGrupos(Excel excel, String nombre, String columna, List<FilaGrupo> filas) {
  final hoja = excel[nombre];
  _fila(hoja, [_t(columna), _t('Cantidad'), _t('Total pagado'), _t('Promedio')], todo: _encabezado);
  for (final f in filas) {
    _fila(hoja, [_t(f.nombre), _i(f.cantidad), _i(f.total), _i(f.promedio)], estilos: {2: _dinero, 3: _dinero});
  }
  _anchos(hoja, [30, 12, 16, 14]);
}

/// Excel del reporte: hojas Resumen, Compras, Por tipo y Por vendedor.
List<int> excelDeReporte(Reporte r, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Resumen');
  final res = excel['Resumen'];
  _fila(res, [_t('CataLog · Reporte de compras')], todo: _titulo);
  _fila(res, [_t('Período'), _t(r.titulo)]);
  if (comprador.isNotEmpty) _fila(res, [_t('Comprador'), _t(comprador)]);
  _fila(res, [_t('Generado el'), _t(fechaHora(generado ?? DateTime.now()))]);
  _fila(res, []);
  _fila(res, [_t('Total gastado'), _i(r.resumen.total)], estilos: {0: _negrita, 1: _dineroNegrita});
  _fila(res, [_t('Catalíticos'), _i(r.resumen.cantidad)], estilos: {0: _negrita});
  _fila(res, [_t('Promedio por catalítico'), _i(r.resumen.promedio)], estilos: {1: _dinero});
  if (r.anuladas > 0) _fila(res, [_t('Compras anuladas (no suman)'), _i(r.anuladas)]);
  _anchos(res, [28, 30]);

  final hoja = excel['Compras'];
  _fila(hoja, [for (final c in _columnasCompras) _t(c)], todo: _encabezado);
  for (final c in r.compras) {
    _filaCompra(hoja, c);
  }
  _fila(hoja, [_t('TOTAL'), null, null, null, null, _i(r.resumen.total)], estilos: {0: _negrita, 5: _dineroNegrita});
  _anchos(hoja, [18, 14, 8, 20, 20, 12, 11, 11, 9, 16, 24, 11, 11, 24, 10, 18]);

  _hojaGrupos(excel, 'Por tipo', 'Tipo', r.porTipo);
  _hojaGrupos(excel, 'Por vendedor', 'Vendedor', r.porVendedor);
  excel.setDefaultSheet('Resumen');
  return excel.encode()!;
}

/// Excel de un lote escaneado: datos del lote y los catalíticos con su precio.
List<int> excelDeLote(Lote lote, List<ItemLote> items, {String comprador = '', DateTime? generado}) {
  final excel = _nuevo('Lote');
  final hoja = excel['Lote'];
  final activos = items.where((i) => !i.compra.anulada).toList();
  final total = activos.fold<int>(0, (s, i) => s + i.compra.precio);

  _fila(hoja, [_t('CataLog · ${lote.nombre}')], todo: _titulo);
  _fila(hoja, [_t('Creado el'), _t(fechaHora(lote.creadoEn))]);
  if (lote.cerradoEn != null) _fila(hoja, [_t('Cerrado el'), _t(fechaHora(lote.cerradoEn!))]);
  if (comprador.isNotEmpty) _fila(hoja, [_t('Comprador'), _t(comprador)]);
  _fila(hoja, [_t('Generado el'), _t(fechaHora(generado ?? DateTime.now()))]);
  _fila(hoja, [_t('Catalíticos'), _i(activos.length)], estilos: {0: _negrita});
  _fila(hoja, [_t('Total pagado'), _i(total)], estilos: {0: _negrita, 1: _dineroNegrita});
  _fila(hoja, []);

  _fila(hoja, [
    _t('Código'), _t('Fecha de compra'), _t('Hora'), _t('Vendedor'), _t('Tipo'),
    _t('Código de fábrica'), _t('Autos'), _t('Precio'), _t('Escaneado el'), _t('Estado'),
  ], todo: _encabezado);
  for (final i in items.reversed) {
    final c = i.compra;
    _fila(hoja, [
      _t(c.codigo), _d(c.fechaCompra), _h(c.fechaCompra), _t(c.vendedor), _t(c.tipo),
      _t(c.codigoFabrica), _t(c.autos), _i(c.precio), _t(fechaHora(i.escaneadoEn)),
      _t(c.anulada ? 'Anulada' : 'Activa'),
    ], estilos: {1: _fecha, 2: _hora, 7: _dinero});
  }
  _fila(hoja, [_t('TOTAL'), null, null, null, null, null, null, _i(total)],
      estilos: {0: _negrita, 7: _dineroNegrita});
  _anchos(hoja, [18, 14, 8, 20, 26, 16, 24, 12, 18, 10]);
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
      XFile(archivo.path,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    ],
    text: texto,
  ));
}
