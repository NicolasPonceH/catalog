import 'package:catalog/data/base.dart';
import 'package:catalog/data/compra.dart';
import 'package:catalog/data/compras_repo.dart';
import 'package:catalog/data/lotes_repo.dart';
import 'package:catalog/domain/tipos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late CatalogDb base;
  late ComprasRepo compras;
  late LotesRepo lotes;
  final reloj = DateTime(2026, 11, 21, 16, 0);

  Future<Compra> compra(int precio) => compras.crear(DatosCompra(
        fechaCompra: DateTime(2026, 11, 21, 9),
        vendedor: 'Juan',
        precio: precio,
        motor: Motor.bencinero,
        material: TipoMaterial.ceramico,
      ));

  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('es');
  });

  setUp(() async {
    base = await CatalogDb.abrir(ruta: inMemoryDatabasePath, fabrica: databaseFactoryFfi);
    compras = ComprasRepo(base, reloj: () => reloj);
    lotes = LotesRepo(base, reloj: () => reloj);
  });

  tearDown(() => base.cerrar());

  test('suma lo pagado por los catalíticos escaneados', () async {
    final a = await compra(180000);
    final b = await compra(95000);
    await compra(60000); // no se escanea
    final lote = await lotes.crear();
    expect(lote.nombre, 'Lote 21/11/2026 · 16:00');

    expect((await lotes.agregarEscaneado(lote.id, a.codigo)).$1, ResultadoEscaneo.agregado);
    // El código de barras viene sin guiones.
    expect((await lotes.agregarEscaneado(lote.id, b.codigo.replaceAll('-', ''))).$1, ResultadoEscaneo.agregado);

    final r = await lotes.resumen(lote.id);
    expect(r.cantidad, 2);
    expect(r.total, 275000);
    expect((await lotes.items(lote.id)).length, 2);
  });

  test('no cuenta dos veces el mismo catalítico', () async {
    final a = await compra(180000);
    final lote = await lotes.crear(nombre: 'Entrega');
    await lotes.agregarEscaneado(lote.id, a.codigo);
    expect((await lotes.agregarEscaneado(lote.id, a.codigo)).$1, ResultadoEscaneo.yaEstaba);
    expect((await lotes.resumen(lote.id)).total, 180000);
  });

  test('avisa si la compra está anulada, no existe o no es un código', () async {
    final a = await compra(180000);
    await compras.anular(a.id, 'error');
    final lote = await lotes.crear();
    expect((await lotes.agregarEscaneado(lote.id, a.codigo)).$1, ResultadoEscaneo.anulada);
    expect((await lotes.agregarEscaneado(lote.id, 'CTL-261121-9999')).$1, ResultadoEscaneo.noExiste);
    expect((await lotes.agregarEscaneado(lote.id, 'https://otra-cosa')).$1, ResultadoEscaneo.noEsCodigo);
    expect((await lotes.resumen(lote.id)).cantidad, 0);
  });

  test('lista los lotes con su total y permite quitar, cerrar y borrar', () async {
    final a = await compra(100000);
    final b = await compra(50000);
    final lote = await lotes.crear(nombre: 'Lote A');
    await lotes.agregarEscaneado(lote.id, a.codigo);
    await lotes.agregarEscaneado(lote.id, b.codigo);
    await lotes.quitar(lote.id, b.id);
    await lotes.cerrar(lote.id);

    final lista = await lotes.listar();
    expect(lista.single.resumen.total, 100000);
    expect(lista.single.lote.cerrado, isTrue);

    await lotes.eliminar(lote.id);
    expect(await lotes.listar(), isEmpty);
    expect(await compras.obtener(a.id), isNotNull, reason: 'borrar el lote no borra compras');
  });
}
