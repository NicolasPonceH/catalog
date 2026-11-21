import 'package:catalog/domain/codigo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('código del catalítico', () {
    test('lleva prefijo, fecha de compra y número del día', () {
      expect(
        formatearCodigo('ctl', DateTime(2026, 11, 21, 10, 42), 7),
        'CTL-261121-0007',
      );
      expect(diaClave(DateTime(2026, 1, 5)), '260105');
    });

    test('usa la fecha de compra aunque se anote otro día', () {
      // Comprado el 20/11 en la tarde, anotado el 21/11: el código dice 20/11.
      final compra = DateTime(2026, 11, 20, 18, 30);
      expect(formatearCodigo('CTL', compra, 1), 'CTL-261120-0001');
    });

    test('el prefijo es de 2 a 5 letras', () {
      expect(validarPrefijo('CTL'), isNull);
      expect(validarPrefijo(' ctt '), isNull);
      expect(validarPrefijo('C'), isNotNull);
      expect(validarPrefijo('CT1'), isNotNull);
      expect(validarPrefijo('ABCDEF'), isNotNull);
      expect(validarPrefijo('C T'), isNotNull);
    });

    test('lee el QR (con guiones) y el código de barras (sin guiones)', () {
      expect(leerCodigoEscaneado('CTL-261121-0007'), 'CTL-261121-0007');
      expect(leerCodigoEscaneado(' ctl2611210007 '), 'CTL-261121-0007');
      expect(leerCodigoEscaneado('CTL-261121-12345'), 'CTL-261121-12345');
      expect(leerCodigoEscaneado('https://ejemplo.cl'), isNull);
      expect(leerCodigoEscaneado('CTL-2611-0007'), isNull);
      expect(codigoParaBarras('CTL-261121-0007'), 'CTL2611210007');
    });
  });

  group('fecha de compra', () {
    final ahora = DateTime(2026, 11, 21, 10, 0);

    test('es obligatoria', () {
      expect(validarFechaCompra(null, ahora), isNotNull);
    });

    test('no puede ser futura (con 5 minutos de margen)', () {
      expect(validarFechaCompra(ahora.add(const Duration(hours: 1)), ahora), isNotNull);
      expect(validarFechaCompra(ahora.add(const Duration(minutes: 3)), ahora), isNull);
    });

    test('acepta fechas pasadas y rechaza las absurdas', () {
      expect(validarFechaCompra(DateTime(2026, 11, 20, 18, 30), ahora), isNull);
      expect(validarFechaCompra(DateTime(1999, 12, 31), ahora), isNotNull);
    });

    test('se guarda al minuto, sin segundos', () {
      expect(alMinuto(DateTime(2026, 11, 21, 10, 42, 37, 120)), DateTime(2026, 11, 21, 10, 42));
    });
  });
}
