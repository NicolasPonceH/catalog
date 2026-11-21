import 'package:catalog/domain/periodos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  test('hoy va de medianoche a medianoche', () {
    final p = periodoHoy(DateTime(2026, 11, 21, 15, 30));
    expect(p.desde, DateTime(2026, 11, 21));
    expect(p.hasta, DateTime(2026, 11, 22));
  });

  test('la semana va de lunes a domingo', () {
    // 21/11/2026 es sábado; la semana parte el lunes 16.
    expect(periodoSemana(DateTime(2026, 11, 21)).desde, DateTime(2026, 11, 16));
    expect(periodoSemana(DateTime(2026, 11, 16, 8)).desde, DateTime(2026, 11, 16));
    expect(periodoSemana(DateTime(2026, 11, 22, 23)).desde, DateTime(2026, 11, 16));
    expect(periodoSemana(DateTime(2026, 11, 21)).hasta, DateTime(2026, 11, 23));
  });

  test('el mes incluye el cambio de año', () {
    final nov = periodoMes(DateTime(2026, 11, 21));
    expect(nov.desde, DateTime(2026, 11, 1));
    expect(nov.hasta, DateTime(2026, 12, 1));
    expect(periodoMes(DateTime(2026, 12, 31)).hasta, DateTime(2027, 1, 1));
  });

  test('los bordes: el inicio cuenta y el final no', () {
    final p = periodoHoy(DateTime(2026, 11, 21));
    expect(p.contiene(DateTime(2026, 11, 21)), isTrue);
    expect(p.contiene(DateTime(2026, 11, 21, 23, 59)), isTrue);
    expect(p.contiene(DateTime(2026, 11, 22)), isFalse);
    expect(p.contiene(DateTime(2026, 11, 20, 23, 59)), isFalse);
  });

  test('un rango incluye el último día completo', () {
    final p = periodoRango(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(p.hasta, DateTime(2026, 12, 1));
    expect(p.contiene(DateTime(2026, 11, 30, 22)), isTrue);
  });
}
