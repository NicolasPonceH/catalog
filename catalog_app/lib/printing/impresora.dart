import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ErrorImpresora implements Exception {
  ErrorImpresora(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

class ImpresoraBt {
  const ImpresoraBt(this.nombre, this.mac);

  final String nombre;
  final String mac;
}

/// Conexión con la impresora térmica por Bluetooth clásico.
/// La impresora se empareja antes en los ajustes de Bluetooth de Android.
class Impresora {
  static String? _conectadaA;

  static Future<void> _asegurarBluetooth() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (r.values.any((s) => s.isPermanentlyDenied)) {
      throw ErrorImpresora('CataLog no tiene permiso de Bluetooth. Actívalo en Ajustes de '
          'Android > Apps > CataLog > Permisos > Dispositivos cercanos.');
    }
    if (r[Permission.bluetoothConnect]?.isGranted != true) {
      throw ErrorImpresora('Se necesita el permiso de "Dispositivos cercanos" para usar la impresora.');
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw ErrorImpresora('El Bluetooth del teléfono está apagado.');
    }
  }

  /// Equipos Bluetooth emparejados con el teléfono.
  static Future<List<ImpresoraBt>> emparejadas() async {
    await _asegurarBluetooth();
    final lista = await PrintBluetoothThermal.pairedBluetooths;
    return [for (final b in lista) ImpresoraBt(b.name, b.macAdress)];
  }

  /// Envía el trabajo completo. Mantiene la conexión abierta para la próxima
  /// impresión (así reimprimir es inmediato).
  static Future<void> imprimir(String mac, List<int> bytes) async {
    await _asegurarBluetooth();
    final yaConectada = _conectadaA == mac && await PrintBluetoothThermal.connectionStatus;
    if (!yaConectada) {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac)
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!ok) {
        _conectadaA = null;
        throw ErrorImpresora('No se pudo conectar con la impresora. Revisa que esté encendida, '
            'con papel y cerca del teléfono.');
      }
      _conectadaA = mac;
    }
    final enviado = await PrintBluetoothThermal.writeBytes(bytes);
    if (!enviado) {
      _conectadaA = null;
      throw ErrorImpresora('La impresora no recibió el sticker. Intenta de nuevo.');
    }
  }

  static Future<void> desconectar() async {
    _conectadaA = null;
    await PrintBluetoothThermal.disconnect;
  }
}
