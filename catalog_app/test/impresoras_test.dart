import 'dart:typed_data';

import 'package:catalog/printing/gato.dart';
import 'package:catalog/printing/impresora.dart';
import 'package:catalog/printing/raster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mini impresoras de AliExpress', () {
    test('el CRC y los paquetes coinciden con los de las apps originales', () {
      // Calidad 200 ppp: 51 78 A4 00 01 00 32 9E FF
      expect(paqueteGato(0xA4, [0x32]), [0x51, 0x78, 0xA4, 0x00, 0x01, 0x00, 0x32, 0x9E, 0xFF]);
      // Estado del equipo: 51 78 A3 00 01 00 00 00 FF
      expect(paqueteGato(0xA3, [0x00]), [0x51, 0x78, 0xA3, 0x00, 0x01, 0x00, 0x00, 0x00, 0xFF]);
      // Inicio y fin de imagen.
      expect(crc8([0xAA, 0x55, 0x17, 0x38, 0x44, 0x5F, 0x5F, 0x5F, 0x44, 0x38, 0x2C]), 0xA1);
      expect(crc8([0xAA, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17]), 0x11);
      // Avance de papel: 51 78 A1 00 02 00 30 00 F9 FF
      expect(paqueteGato(0xA1, [0x30, 0x00]), [0x51, 0x78, 0xA1, 0x00, 0x02, 0x00, 0x30, 0x00, 0xF9, 0xFF]);
    });

    test('cada fila va en su paquete con los bits al revés', () {
      final bits = Uint8List(48 * 2);
      bits[0] = 0x80; // punto (0,0) negro
      bits[48 + 47] = 0x01; // último punto de la segunda fila
      final trabajo = trabajoGato(BitmapMono(384, 2, bits));

      // 5 paquetes de preparación + 2 filas de 48 bytes + 3 paquetes de cierre.
      final preparacion = 9 + 9 + 10 + 9 + 19;
      final fila = 6 + 48 + 2;
      expect(trabajo.length, preparacion + 2 * fila + 10 + 19 + 9);

      final primera = trabajo.sublist(preparacion, preparacion + fila);
      expect(primera.sublist(0, 6), [0x51, 0x78, 0xA2, 0x00, 48, 0x00]);
      expect(primera[6], 0x01, reason: 'el punto de la izquierda va en el bit bajo');
      final segunda = trabajo.sublist(preparacion + fila, preparacion + 2 * fila);
      expect(segunda[6 + 47], 0x80);
    });

    test('solo acepta 384 puntos de ancho', () {
      expect(() => trabajoGato(BitmapMono(576, 1, Uint8List(72))), throwsArgumentError);
    });

    test('entiende las pausas que pide la impresora', () {
      expect(leerControlDeFlujo([0x51, 0x78, 0xAE, 0x01, 0x01, 0x00, 0x10, 0x70, 0xFF]), isTrue);
      expect(leerControlDeFlujo([0x51, 0x78, 0xAE, 0x01, 0x01, 0x00, 0x00, 0x00, 0xFF]), isFalse);
      expect(leerControlDeFlujo([0x51, 0x78, 0xA3, 0x01, 0x01, 0x00, 0x00, 0x00, 0xFF]), isNull);
    });
  });

  group('detección automática del tipo de impresora BLE', () {
    const largo = '-0000-1000-8000-00805f9b34fb';
    const generico = ServicioBle('00001800$largo', [CaracteristicaBle('00002a00$largo', escribe: true)]);

    test('reconoce una mini impresora por su servicio AE30', () {
      final canal = elegirCanalBle([
        generico,
        const ServicioBle('0000ae30$largo', [
          CaracteristicaBle('0000ae01$largo', escribeSinRespuesta: true),
          CaracteristicaBle('0000ae02$largo', notifica: true),
        ]),
      ])!;
      expect(canal.protocolo, Protocolo.gato);
      expect(uuidCorto(canal.caracteristica), 'ae01');
      expect(uuidCorto(canal.notificacion!), 'ae02');
      expect(canal.sinRespuesta, isTrue);
    });

    test('reconoce impresoras ESC/POS BLE comunes', () {
      final canal = elegirCanalBle([
        generico,
        const ServicioBle('000018f0$largo', [
          CaracteristicaBle('00002af0$largo', notifica: true),
          CaracteristicaBle('00002af1$largo', escribe: true, escribeSinRespuesta: true),
        ]),
      ])!;
      expect(canal.protocolo, Protocolo.escpos);
      expect(uuidCorto(canal.caracteristica), '2af1');
    });

    test('si no la conoce, usa cualquier canal de escritura que no sea estándar', () {
      final canal = elegirCanalBle([
        generico,
        const ServicioBle('12345678-0000-4000-8000-000000000000', [
          CaracteristicaBle('12345678-0001-4000-8000-000000000000', escribe: true),
        ]),
      ])!;
      expect(canal.protocolo, Protocolo.escpos);
      expect(canal.sinRespuesta, isFalse);
    });

    test('un equipo sin canal para escribir no es impresora', () {
      expect(elegirCanalBle([generico]), isNull);
    });

    test('la impresora elegida se guarda y se recupera', () {
      const imp = ImpresoraGuardada(
        nombre: 'MX06',
        id: 'AA:BB:CC:DD:EE:FF',
        conexion: Conexion.ble,
        protocolo: Protocolo.gato,
        servicio: '0000ae30$largo',
        caracteristica: '0000ae01$largo',
        notificacion: '0000ae02$largo',
      );
      final leida = ImpresoraGuardada.deTexto(imp.aTexto())!;
      expect(leida.protocolo, Protocolo.gato);
      expect(leida.descripcion, 'Bluetooth BLE · mini impresora');
      expect(leida.soloAnchoChico, isTrue);
      expect(ImpresoraGuardada.deTexto('basura'), isNull);
    });
  });
}
