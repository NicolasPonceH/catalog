import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/domain/periodos.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late CatalogDb base;
  late ComprasRepo repo;
  var reloj = DateTime(2026, 11, 21, 10, 0);

  DatosCompra datos({
    DateTime? fecha,
    String vendedor = 'Juan Pérez',
    int precio = 180000,
    String lugar = 'Feria Agro',
    String autos = 'Toyota Yaris 2008-2013',
    TipoMaterial material = TipoMaterial.ceramico,
  }) =>
      DatosCompra(
        fechaCompra: fecha ?? DateTime(2026, 11, 21, 9, 30),
        vendedor: vendedor,
        lugar: lugar,
        precio: precio,
        motor: Motor.bencinero,
        material: material,
        autos: autos,
      );

  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  setUp(() async {
    reloj = DateTime(2026, 11, 21, 10, 0);
    base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
    repo = ComprasRepo(base, reloj: () => reloj);
  });

  tearDown(() => base.cerrar());

  group('fecha de compra y código', () {
    test('numera por día de compra', () async {
      final a = await repo.crear(datos());
      final b = await repo.crear(datos());
      expect(a.codigo, 'CTL-261121-0001');
      expect(b.codigo, 'CTL-261121-0002');
      expect(a.fechaCompra, DateTime(2026, 11, 21, 9, 30));
    });

    test('una compra anotada al día siguiente queda con su fecha real', () async {
      final ayer = await repo.crear(datos(fecha: DateTime(2026, 11, 20, 18, 45)));
      expect(ayer.codigo, 'CTL-261120-0001');
      expect(ayer.fechaCompra, DateTime(2026, 11, 20, 18, 45));
      expect(ayer.creadoEn, reloj);
      final hist = await repo.historial(FiltroHistorial(periodo: periodoHoy(DateTime(2026, 11, 20))));
      expect(hist.map((c) => c.codigo), ['CTL-261120-0001']);
    });

    test('rechaza fechas futuras y compras sin vendedor', () async {
      expect(
        () => repo.crear(datos(fecha: reloj.add(const Duration(hours: 2)))),
        throwsA(isA<DatosInvalidos>()),
      );
      expect(() => repo.crear(datos(vendedor: '  ')), throwsA(isA<DatosInvalidos>()));
    });

    test('usa el prefijo de este teléfono', () async {
      await repo.guardarAjuste('prefijo', 'CTT');
      expect((await repo.crear(datos())).codigo, 'CTT-261121-0001');
    });

    test('un número anulado nunca se vuelve a usar', () async {
      final a = await repo.crear(datos());
      await repo.anular(a.id, 'Error de digitación');
      final b = await repo.crear(datos());
      expect(b.codigo, 'CTL-261121-0002');
    });

    test('corregir la fecha queda registrado; otros cambios no', () async {
      final c = await repo.crear(datos());
      reloj = DateTime(2026, 11, 21, 12, 0);
      await repo.actualizar(c.id, datos(precio: 200000));
      var leida = (await repo.obtener(c.id))!;
      expect(leida.precio, 200000);
      expect(leida.fechaCompraEditadaEn, isNull);
      expect(leida.codigo, c.codigo);

      await repo.actualizar(c.id, datos(fecha: DateTime(2026, 11, 21, 8, 0)));
      leida = (await repo.obtener(c.id))!;
      expect(leida.fechaCompra, DateTime(2026, 11, 21, 8, 0));
      expect(leida.fechaCompraEditadaEn, DateTime(2026, 11, 21, 12, 0));
      expect(leida.codigo, 'CTL-261121-0001', reason: 'el código impreso no cambia');
    });
  });

  group('totales e historial', () {
    test('el resumen usa la fecha de compra y excluye anuladas', () async {
      await repo.crear(datos(precio: 100000));
      await repo.crear(datos(precio: 50000));
      final anulada = await repo.crear(datos(precio: 30000));
      await repo.crear(datos(precio: 999000, fecha: DateTime(2026, 10, 31, 23, 59)));
      await repo.anular(anulada.id, 'Repetida');

      final mes = await repo.resumen(periodoMes(reloj));
      expect(mes.cantidad, 2);
      expect(mes.total, 150000);
      expect(mes.promedio, 75000);
      final octubre = await repo.resumen(periodoMes(DateTime(2026, 10, 15)));
      expect(octubre.total, 999000);
    });

    test('busca por texto, filtra por material y ordena por fecha', () async {
      await repo.crear(datos(vendedor: 'Pedro Soto', fecha: DateTime(2026, 11, 21, 8)));
      await repo.crear(datos(
        vendedor: 'Taller Norte',
        autos: 'Hyundai Accent',
        material: TipoMaterial.metalico,
        fecha: DateTime(2026, 11, 21, 9),
      ));
      await repo.crear(datos(vendedor: 'Pedro Soto', fecha: DateTime(2026, 11, 19, 15)));

      final todas = await repo.historial(const FiltroHistorial());
      expect(todas.map((c) => c.fechaCompra.day), [21, 21, 19]);
      expect(todas.first.vendedor, 'Taller Norte');

      expect((await repo.historial(const FiltroHistorial(texto: 'pedro'))).length, 2);
      expect((await repo.historial(const FiltroHistorial(texto: 'accent'))).length, 1);
      expect(
        (await repo.historial(const FiltroHistorial(material: TipoMaterial.metalico))).single.vendedor,
        'Taller Norte',
      );
    });

    test('sugiere vendedores usados más recientemente primero', () async {
      await repo.crear(datos(vendedor: 'Ana', fecha: DateTime(2026, 11, 1)));
      await repo.crear(datos(vendedor: 'Beto', fecha: DateTime(2026, 11, 20)));
      await repo.crear(datos(vendedor: 'Ana', fecha: DateTime(2026, 11, 2)));
      expect(await repo.sugerencias('vendedor'), ['Beto', 'Ana']);
    });
  });
}
