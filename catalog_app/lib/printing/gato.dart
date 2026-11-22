// Protocolo de las mini impresoras térmicas baratas de AliExpress (modelos tipo
// GB01, GB02, MX05, MX06, MX10, YT01…, que usan apps como iPrint o Fun Print).
// No entienden ESC/POS: reciben paquetes propios por Bluetooth BLE.
//
// Paquete: 51 78 COMANDO 00 LARGO_L LARGO_H DATOS... CRC8(DATOS) FF

import 'raster.dart';

/// CRC-8 (polinomio 0x07) de los datos del paquete.
int crc8(List<int> datos) {
  var crc = 0;
  for (final b in datos) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

List<int> paqueteGato(int comando, List<int> datos) => [
      0x51, 0x78, comando, 0x00, datos.length & 0xFF, (datos.length >> 8) & 0xFF,
      ...datos,
      crc8(datos),
      0xFF,
    ];

const _comandoEstado = 0xA3;
const _comandoCalidad = 0xA4;
const _comandoEnergia = 0xAF;
const _comandoAplicarEnergia = 0xBE;
const _comandoInicioFin = 0xA6;
const _comandoLinea = 0xA2;
const _comandoAvance = 0xA1;

const _inicioImagen = [0xAA, 0x55, 0x17, 0x38, 0x44, 0x5F, 0x5F, 0x5F, 0x44, 0x38, 0x2C];
const _finImagen = [0xAA, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17];

/// Estas impresoras esperan el punto de más a la izquierda en el bit más bajo.
int _invertirBits(int b) {
  var r = 0;
  for (var i = 0; i < 8; i++) {
    if (b & (1 << i) != 0) r |= 0x80 >> i;
  }
  return r;
}

/// Trabajo completo para una mini impresora (siempre 384 puntos de ancho).
/// [energia] controla qué tan oscuro sale (más alto = más oscuro).
List<int> trabajoGato(BitmapMono b, {int energia = 0xC000, int avance = 90}) {
  if (b.ancho != 384) {
    throw ArgumentError('Las mini impresoras imprimen 384 puntos de ancho (papel de 58 mm)');
  }
  final salida = <int>[
    ...paqueteGato(_comandoEstado, [0x00]),
    ...paqueteGato(_comandoCalidad, [0x32]), // 200 ppp
    ...paqueteGato(_comandoEnergia, [energia & 0xFF, (energia >> 8) & 0xFF]),
    ...paqueteGato(_comandoAplicarEnergia, [0x01]),
    ...paqueteGato(_comandoInicioFin, _inicioImagen),
  ];
  for (var y = 0; y < b.alto; y++) {
    final inicio = y * b.anchoBytes;
    salida.addAll(paqueteGato(_comandoLinea, [
      for (var x = 0; x < b.anchoBytes; x++) _invertirBits(b.bits[inicio + x]),
    ]));
  }
  salida
    ..addAll(paqueteGato(_comandoAvance, [avance & 0xFF, (avance >> 8) & 0xFF]))
    ..addAll(paqueteGato(_comandoInicioFin, _finImagen))
    ..addAll(paqueteGato(_comandoEstado, [0x00]));
  return salida;
}

/// La impresora pide pausa (0x10) o reanudar (0x00) con el comando 0xAE.
/// Devuelve true = pausa, false = reanudar, null = otro mensaje.
bool? leerControlDeFlujo(List<int> v) {
  if (v.length < 7 || v[0] != 0x51 || v[1] != 0x78 || v[2] != 0xAE) return null;
  return v[6] == 0x10;
}
