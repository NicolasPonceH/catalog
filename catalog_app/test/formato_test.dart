import 'package:catalog/domain/formato.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('pesos chilenos', () {
    test('sin decimales y con punto de miles', () {
      expect(clp(0), r'$0');
      expect(clp(950), r'$950');
      expect(clp(1000), r'$1.000');
      expect(clp(180000), r'$180.000');
      expect(clp(1250000), r'$1.250.000');
    });

    test('lee montos escritos con o sin puntos', () {
      expect(parseClp('180.000'), 180000);
      expect(parseClp(r'$ 1.250.000'), 1250000);
      expect(parseClp(''), isNull);
      expect(parseClp('abc'), isNull);
    });

    test('formatea el precio mientras se escribe', () {
      final r = ClpInputFormatter().formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '180000'),
      );
      expect(r.text, '180.000');
      expect(r.selection.baseOffset, 7);
    });
  });

  group('fechas', () {
    final f = DateTime(2026, 11, 21, 9, 5);

    test('formato corto, hora y largo en español', () {
      expect(fechaCorta(f), '21/11/2026');
      expect(hora(f), '09:05');
      expect(fechaHora(f), '21/11/2026 · 09:05');
      expect(fechaLarga(f), 'sábado 21 de noviembre de 2026');
      expect(nombreMes(f), 'Noviembre 2026');
    });

    test('encabezados del historial', () {
      final hoy = DateTime(2026, 11, 21, 8);
      expect(encabezadoDia(DateTime(2026, 11, 21, 23, 59), hoy), 'Hoy');
      expect(encabezadoDia(DateTime(2026, 11, 20, 0, 1), hoy), 'Ayer');
      expect(encabezadoDia(DateTime(2026, 11, 19), hoy), startsWith('Jue'));
    });

    test('cuenta días bien aunque cambie el horario de verano', () {
      // Chile adelanta la hora a comienzos de septiembre.
      expect(diasEntre(DateTime(2026, 9, 5, 23), DateTime(2026, 9, 6, 1)), 1);
      expect(diasEntre(DateTime(2026, 4, 4, 12), DateTime(2026, 4, 5, 12)), 1);
    });
  });
}
