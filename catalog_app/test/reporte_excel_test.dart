import 'package:catalog/data/compra.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:catalog/reports/excel.dart';
import 'package:catalog/reports/reporte.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

var _id = 0;
Compra compra({
  required int precio,
  String vendedor = 'Juan Pérez',
  Motor motor = Motor.bencinero,
  TipoMaterial material = TipoMaterial.ceramico,
  bool anulada = false,
  DateTime? fecha,
}) {
  _id++;
  final f = fecha ?? DateTime(2026, 11, 21, 9, _id);
  return Compra(
    id: _id,
    codigo: 'CTL-261121-${_id.toString().padLeft(4, '0')}',
    fechaCompra: f,
    vendedor: vendedor,
    lugar: 'Feria Agro',
    lat: -18.48,
    lng: -70.31,
    precio: precio,
    motor: motor,
    material: material,
    original: false,
    codigoFabrica: '0D140',
    autos: 'Toyota Yaris',
    notas: '',
    anulada: anulada,
    motivoAnulacion: '',
    impresiones: 0,
    creadoEn: f,
    actualizadoEn: f,
  );
}

int? entero(CellValue? v) => v is IntCellValue ? v.value : null;
String? texto(CellValue? v) => v is TextCellValue ? v.value.toString() : null;

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  final compras = [
    compra(precio: 180000, vendedor: 'Juan Pérez'),
    compra(precio: 95000, vendedor: 'Taller Norte', material: TipoMaterial.metalico),
    compra(precio: 60000, vendedor: 'juan pérez'),
    compra(precio: 300000, vendedor: 'Pedro', motor: Motor.diesel, material: TipoMaterial.dpf),
    compra(precio: 999999, vendedor: 'Pedro', anulada: true),
  ];

  test('el reporte suma solo las compras activas y agrupa por tipo y vendedor', () {
    final r = Reporte.de(compras, titulo: 'Noviembre 2026');
    expect(r.resumen.cantidad, 4);
    expect(r.resumen.total, 635000);
    expect(r.anuladas, 1);

    expect(r.porTipo.first.nombre, 'DPF · Diésel');
    expect(r.porTipo.map((f) => f.nombre), containsAll(['Cerámico · Bencinero', 'Metálico · Bencinero']));
    final ceramico = r.porTipo.firstWhere((f) => f.nombre == 'Cerámico · Bencinero');
    expect(ceramico.cantidad, 2);
    expect(ceramico.total, 240000);

    // "Juan Pérez" y "juan pérez" son el mismo vendedor.
    final juan = r.porVendedor.firstWhere((f) => f.nombre == 'Juan Pérez');
    expect(juan.cantidad, 2);
    expect(juan.promedio, 120000);
    expect(r.porVendedor.first.nombre, 'Pedro', reason: 'ordenado por total');
    expect(r.porVendedor.first.total, 300000, reason: 'la anulada no suma');
  });

  test('el Excel del reporte tiene sus hojas y los totales cuadran', () {
    final bytes = excelDeReporte(Reporte.de(compras, titulo: 'Noviembre 2026'), comprador: 'Papá');
    final excel = Excel.decodeBytes(bytes);
    expect(excel.tables.keys, containsAll(['Resumen', 'Compras']));

    // Resumen: tarjeta "TOTAL GASTADO" con el valor en la fila de abajo.
    final res = excel['Resumen'];
    final filas = res.rows;
    final i = filas.indexWhere((f) => texto(f.first?.value) == 'TOTAL GASTADO');
    expect(i, greaterThan(0));
    expect(entero(filas[i + 1].first?.value), 635000);
    expect(filas.any((f) => texto(f.first?.value) == 'Por tipo de catalítico'), isTrue);
    expect(filas.any((f) => texto(f.first?.value) == 'Por vendedor'), isTrue);
    expect(filas.any((f) => texto(f.first?.value) == 'DPF · Diésel'), isTrue);

    final hoja = excel['Compras'];
    expect(texto(hoja.rows.first.first?.value), 'Código');
    // Encabezado + 5 compras (incluida la anulada) + fila TOTAL.
    expect(hoja.maxRows, 7);
    final ultima = hoja.rows.last;
    expect(texto(ultima.first?.value), startsWith('TOTAL'));
    expect(entero(ultima[8]?.value), 635000);
    final anulada = hoja.rows.firstWhere((f) => texto(f[9]?.value) == 'Anulada');
    expect(entero(anulada[8]?.value), 999999);
    // La fecha de compra va como fecha real de Excel y hay enlace al mapa.
    expect(hoja.rows[1][1]?.value, isA<DateCellValue>());
    expect(hoja.rows[1][10]?.value, isA<FormulaCellValue>());
    // Ya no existe la columna "Original".
    expect(hoja.rows.first.map((c) => texto(c?.value)), isNot(contains('Original')));
  });

  test('el Excel del lote lista los catalíticos y su total', () {
    final lote = Lote(id: 1, nombre: 'Entrega fundición', creadoEn: DateTime(2026, 11, 21, 16), notas: '');
    final items = [for (final c in compras.take(3)) ItemLote(c, DateTime(2026, 11, 21, 16))];
    final excel = Excel.decodeBytes(excelDeLote(lote, items));
    final hoja = excel['Lote'];
    final i = hoja.rows.indexWhere((f) => texto(f.first?.value) == 'TOTAL PAGADO');
    expect(entero(hoja.rows[i + 1].first?.value), 335000);
    expect(texto(hoja.rows.last.first?.value), 'TOTAL');
    expect(entero(hoja.rows.last[7]?.value), 335000);
  });
}
