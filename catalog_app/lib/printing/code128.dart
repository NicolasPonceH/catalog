// Código de barras Code 128 (juegos B y C), escrito sin dependencias para
// dibujarlo igual en pantalla y en la impresora térmica.
//
// Cada símbolo son 3 barras y 3 espacios; los números indican el ancho de
// cada uno en módulos (suman 11). El de parada tiene 7 elementos (13 módulos).

const patronesCode128 = <String>[
  '212222', '222122', '222221', '121223', '121322', '131222', '122213', '122312', //   0-7
  '132212', '221213', '221312', '231212', '112232', '122132', '122231', '113222', //   8-15
  '123122', '123221', '223211', '221132', '221231', '213212', '223112', '312131', //  16-23
  '311222', '321122', '321221', '312212', '322112', '322211', '212123', '212321', //  24-31
  '232121', '111323', '131123', '131321', '112313', '132113', '132311', '211313', //  32-39
  '231113', '231311', '112133', '112331', '132131', '113123', '113321', '133121', //  40-47
  '313121', '211331', '231131', '213113', '213311', '213131', '311123', '311321', //  48-55
  '331121', '312113', '312311', '332111', '314111', '221411', '431111', '111224', //  56-63
  '111422', '121124', '121421', '141122', '141221', '112214', '112412', '122114', //  64-71
  '122411', '142112', '142211', '241211', '221114', '413111', '241112', '134111', //  72-79
  '111242', '121142', '121241', '114212', '124112', '124211', '411212', '421112', //  80-87
  '421211', '212141', '214121', '412121', '111143', '111341', '131141', '114113', //  88-95
  '114311', '411113', '411311', '113141', '114131', '311141', '411131', '211412', //  96-103
  '211214', '211232', '2331112', //                                                  104-106
];

const _inicioB = 104;
const _inicioC = 105;
const _cambiarAC = 99;
const _cambiarAB = 100;
const _parada = 106;

/// Margen blanco recomendado a cada lado, en módulos.
const margenCode128 = 10;

bool _esDigito(int c) => c >= 48 && c <= 57;

/// Valores de los símbolos: inicio, datos, dígito verificador y parada.
/// Usa el juego C (pares de dígitos) en tramos largos de números.
List<int> valoresCode128(String texto) {
  if (texto.isEmpty) throw ArgumentError('El texto está vacío');
  for (final c in texto.codeUnits) {
    if (c < 32 || c > 126) throw ArgumentError('Carácter no válido en Code 128: $c');
  }
  int digitosDesde(int i) {
    var n = 0;
    while (i + n < texto.length && _esDigito(texto.codeUnitAt(i + n))) {
      n++;
    }
    return n;
  }

  final valores = <int>[];
  var enC = false;
  final inicial = digitosDesde(0);
  if (inicial >= 4 && inicial.isEven) {
    valores.add(_inicioC);
    enC = true;
  } else {
    valores.add(_inicioB);
  }

  var i = 0;
  while (i < texto.length) {
    final tramo = digitosDesde(i);
    if (enC) {
      if (tramo >= 2) {
        valores.add(int.parse(texto.substring(i, i + 2)));
        i += 2;
      } else {
        valores.add(_cambiarAB);
        enC = false;
      }
      continue;
    }
    final llegaAlFinal = i + tramo == texto.length;
    if (tramo >= 4 && tramo.isEven && (tramo >= 6 || llegaAlFinal)) {
      valores.add(_cambiarAC);
      enC = true;
      continue;
    }
    valores.add(texto.codeUnitAt(i) - 32);
    i++;
  }

  var suma = valores.first;
  for (var k = 1; k < valores.length; k++) {
    suma += valores[k] * k;
  }
  valores
    ..add(suma % 103)
    ..add(_parada);
  return valores;
}

/// Módulos del código (true = barra negra), sin los márgenes blancos.
List<bool> modulosCode128(String texto) {
  final modulos = <bool>[];
  for (final v in valoresCode128(texto)) {
    var negro = true;
    for (final ancho in patronesCode128[v].codeUnits) {
      for (var k = 0; k < ancho - 48; k++) {
        modulos.add(negro);
      }
      negro = !negro;
    }
  }
  return modulos;
}
