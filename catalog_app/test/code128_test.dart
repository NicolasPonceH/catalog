import 'package:catalog/printing/code128.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la tabla tiene 107 símbolos de 11 módulos (la parada 13)', () {
    expect(patronesCode128.length, 107);
    for (var v = 0; v < 106; v++) {
      final suma = patronesCode128[v].codeUnits.fold<int>(0, (s, c) => s + c - 48);
      expect(suma, 11, reason: 'símbolo $v');
      expect(patronesCode128[v].length, 6, reason: 'símbolo $v');
    }
    expect(patronesCode128[106].codeUnits.fold<int>(0, (s, c) => s + c - 48), 13);
    expect(patronesCode128.toSet().length, 107, reason: 'no hay patrones repetidos');
  });

  test('el código del sticker usa letras en B y los números en pares (C)', () {
    // Inicio B, C T L, cambio a C, 26 11 21 00 07, verificador, parada.
    expect(valoresCode128('CTL2611210007'), [104, 35, 52, 44, 99, 26, 11, 21, 0, 7, 44, 106]);
    // 12 símbolos de 11 módulos + parada de 13 = 134 módulos: cabe en 58 mm a 2 puntos.
    expect(modulosCode128('CTL2611210007').length, 134);
  });

  test('solo números parte directo en C', () {
    expect(valoresCode128('1234'), [105, 12, 34, (105 + 12 + 34 * 2) % 103, 106]);
  });

  test('tramos cortos de números se quedan en B', () {
    final v = valoresCode128('PJJ123C');
    expect(v.first, 104);
    expect(v.contains(99), isFalse);
    expect(v.length, 1 + 7 + 2);
  });

  test('empieza y termina con barra negra', () {
    final m = modulosCode128('CTL2611210007');
    expect(m.first, isTrue);
    expect(m.last, isTrue);
  });

  test('rechaza caracteres que Code 128 B no tiene', () {
    expect(() => valoresCode128('Ñandú'), throwsArgumentError);
    expect(() => valoresCode128(''), throwsArgumentError);
  });
}
