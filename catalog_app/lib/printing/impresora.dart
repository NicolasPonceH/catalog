import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:universal_ble/universal_ble.dart';

import 'escpos.dart';
import 'gato.dart';
import 'raster.dart';

class ErrorImpresora implements Exception {
  ErrorImpresora(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Cómo se conecta: Bluetooth clásico (emparejado en Android) o BLE.
enum Conexion { clasica, ble }

/// Qué "idioma" habla: ESC/POS (la mayoría) o el de las mini impresoras de AliExpress.
enum Protocolo { escpos, gato }

/// Un equipo encontrado al buscar impresoras.
class ImpresoraEncontrada {
  const ImpresoraEncontrada(this.nombre, this.id, this.conexion, {this.rssi});

  final String nombre;
  final String id;
  final Conexion conexion;
  final int? rssi;

  bool get pareceImpresora => pareceNombreDeImpresora(nombre);
}

final _nombresDeImpresora = RegExp(
  r'print|prt|pos|mpt|mtp|gb0|gb1|mx0|mx1|yt0|m0[0-9]|t0[0-9]|pt-|qr|label|thermal|termic|58|80|cat',
  caseSensitive: false,
);

bool pareceNombreDeImpresora(String nombre) => _nombresDeImpresora.hasMatch(nombre);

/// La impresora elegida, con todo lo necesario para imprimir sin volver a buscarla.
class ImpresoraGuardada {
  const ImpresoraGuardada({
    required this.nombre,
    required this.id,
    required this.conexion,
    required this.protocolo,
    this.servicio,
    this.caracteristica,
    this.notificacion,
    this.sinRespuesta = true,
  });

  factory ImpresoraGuardada.deJson(Map<String, dynamic> j) => ImpresoraGuardada(
        nombre: j['nombre'] as String? ?? '',
        id: j['id'] as String,
        conexion: Conexion.values.byName(j['conexion'] as String),
        protocolo: Protocolo.values.byName(j['protocolo'] as String),
        servicio: j['servicio'] as String?,
        caracteristica: j['caracteristica'] as String?,
        notificacion: j['notificacion'] as String?,
        sinRespuesta: j['sinRespuesta'] as bool? ?? true,
      );

  static ImpresoraGuardada? deTexto(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    try {
      return ImpresoraGuardada.deJson(jsonDecode(texto) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  final String nombre;
  final String id;
  final Conexion conexion;
  final Protocolo protocolo;
  final String? servicio;
  final String? caracteristica;
  final String? notificacion;
  final bool sinRespuesta;

  String aTexto() => jsonEncode({
        'nombre': nombre,
        'id': id,
        'conexion': conexion.name,
        'protocolo': protocolo.name,
        'servicio': servicio,
        'caracteristica': caracteristica,
        'notificacion': notificacion,
        'sinRespuesta': sinRespuesta,
      });

  String get descripcion => switch ((conexion, protocolo)) {
        (Conexion.clasica, _) => 'Bluetooth clásico · ESC/POS',
        (Conexion.ble, Protocolo.gato) => 'Bluetooth BLE · mini impresora',
        (Conexion.ble, Protocolo.escpos) => 'Bluetooth BLE · ESC/POS',
      };

  /// Las mini impresoras solo imprimen 384 puntos de ancho.
  bool get soloAnchoChico => protocolo == Protocolo.gato;
}

// ---------- Elegir el canal BLE (sin dependencias, se puede probar) ----------

class CaracteristicaBle {
  const CaracteristicaBle(this.uuid, {this.escribe = false, this.escribeSinRespuesta = false, this.notifica = false});

  final String uuid;
  final bool escribe;
  final bool escribeSinRespuesta;
  final bool notifica;

  bool get sirveParaEscribir => escribe || escribeSinRespuesta;
}

class ServicioBle {
  const ServicioBle(this.uuid, this.caracteristicas);

  final String uuid;
  final List<CaracteristicaBle> caracteristicas;
}

class CanalBle {
  const CanalBle(this.protocolo, this.servicio, this.caracteristica, {this.notificacion, required this.sinRespuesta});

  final Protocolo protocolo;
  final String servicio;
  final String caracteristica;
  final String? notificacion;
  final bool sinRespuesta;
}

/// "0000ae30-0000-1000-8000-00805f9b34fb" -> "ae30".
String uuidCorto(String uuid) {
  final u = uuid.toLowerCase();
  final m = RegExp(r'^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$').firstMatch(u);
  return m?.group(1) ?? u;
}

/// Servicio y característica que usan las impresoras ESC/POS BLE más comunes.
const _paresEscpos = [
  ('18f0', '2af1'),
  ('e7810a71-73ae-499d-8c15-faa9aef0c3f2', 'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f'),
  ('49535343-fe7d-4ae5-8fa9-9fafd205e455', '49535343-8841-43f4-a8d4-ecbe34729bb3'),
  ('ff00', 'ff02'),
  ('ffe0', 'ffe1'),
  ('fff0', 'fff2'),
];

/// Servicios estándar de Bluetooth que nunca son para imprimir.
const _serviciosEstandar = {'1800', '1801', '180a', '180f', '1805', '1812'};

/// Decide cómo imprimir según los servicios BLE del equipo.
CanalBle? elegirCanalBle(List<ServicioBle> servicios) {
  CaracteristicaBle? buscar(ServicioBle s, String corto) {
    for (final c in s.caracteristicas) {
      if (uuidCorto(c.uuid) == corto) return c;
    }
    return null;
  }

  // 1. Mini impresora de AliExpress: servicio AE30, escribe en AE01, avisa en AE02.
  for (final s in servicios) {
    if (uuidCorto(s.uuid) != 'ae30') continue;
    final escribir = buscar(s, 'ae01') ?? s.caracteristicas.where((c) => c.sirveParaEscribir).firstOrNull;
    if (escribir == null) continue;
    final avisa = buscar(s, 'ae02');
    return CanalBle(
      Protocolo.gato,
      s.uuid,
      escribir.uuid,
      notificacion: (avisa?.notifica ?? false) ? avisa!.uuid : null,
      sinRespuesta: escribir.escribeSinRespuesta,
    );
  }

  // 2. Impresoras ESC/POS BLE conocidas.
  for (final (servicio, caracteristica) in _paresEscpos) {
    for (final s in servicios) {
      if (uuidCorto(s.uuid) != servicio) continue;
      final c = buscar(s, caracteristica);
      if (c != null && c.sirveParaEscribir) {
        return CanalBle(Protocolo.escpos, s.uuid, c.uuid, sinRespuesta: c.escribeSinRespuesta);
      }
    }
  }

  // 3. Cualquier característica donde se pueda escribir, fuera de los servicios estándar.
  for (final s in servicios) {
    if (_serviciosEstandar.contains(uuidCorto(s.uuid))) continue;
    for (final c in s.caracteristicas) {
      if (c.sirveParaEscribir) {
        return CanalBle(Protocolo.escpos, s.uuid, c.uuid, sinRespuesta: c.escribeSinRespuesta);
      }
    }
  }
  return null;
}

// ---------- Conexión ----------

/// Impresión por Bluetooth clásico (SPP) o BLE, con ESC/POS o el protocolo de
/// las mini impresoras. Así funciona con casi cualquier impresora térmica.
class Impresora {
  static String? _clasicaConectada;

  static Future<void> _permisos() async {
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
    if (r.values.any((s) => s.isPermanentlyDenied)) {
      throw ErrorImpresora('CataLog no tiene permiso de Bluetooth. Actívalo en Ajustes de '
          'Android > Apps > CataLog > Permisos > Dispositivos cercanos.');
    }
    if (r[Permission.bluetoothConnect]?.isGranted != true) {
      throw ErrorImpresora('Se necesita el permiso de "Dispositivos cercanos" para usar la impresora.');
    }
    // En Android 11 o anterior, buscar equipos BLE requiere el permiso de ubicación.
    try {
      await UniversalBle.requestPermissions();
    } catch (_) {}
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw ErrorImpresora('El Bluetooth del teléfono está apagado.');
    }
  }

  /// Equipos emparejados (clásicos) y equipos BLE cercanos. Los que parecen
  /// impresoras van primero.
  static Future<List<ImpresoraEncontrada>> buscar({Duration duracion = const Duration(seconds: 6)}) async {
    await _permisos();
    final encontradas = <String, ImpresoraEncontrada>{};
    for (final b in await PrintBluetoothThermal.pairedBluetooths) {
      encontradas['c:${b.macAdress}'] = ImpresoraEncontrada(b.name, b.macAdress, Conexion.clasica);
    }
    final sub = UniversalBle.scanStream.listen((d) {
      final nombre = (d.name ?? '').trim();
      if (nombre.isEmpty) return;
      encontradas['b:${d.deviceId}'] = ImpresoraEncontrada(nombre, d.deviceId, Conexion.ble, rssi: d.rssi);
    });
    try {
      await UniversalBle.startScan(skipDuplicates: true);
      await Future<void>.delayed(duracion);
    } catch (_) {
      // Si falla la búsqueda BLE, igual se muestran las emparejadas.
    } finally {
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
      await sub.cancel();
    }
    final lista = encontradas.values.toList()
      ..sort((a, b) {
        if (a.pareceImpresora != b.pareceImpresora) return a.pareceImpresora ? -1 : 1;
        return (b.rssi ?? -200).compareTo(a.rssi ?? -200);
      });
    return lista;
  }

  /// Revisa el equipo elegido y decide cómo imprimirle.
  static Future<ImpresoraGuardada> preparar(ImpresoraEncontrada e) async {
    if (e.conexion == Conexion.clasica) {
      return ImpresoraGuardada(nombre: e.nombre, id: e.id, conexion: Conexion.clasica, protocolo: Protocolo.escpos);
    }
    await _permisos();
    final canal = elegirCanalBle(await _serviciosBle(e.id));
    if (canal == null) {
      throw ErrorImpresora('${e.nombre} no tiene un canal para imprimir. ¿Seguro que es la impresora?');
    }
    return ImpresoraGuardada(
      nombre: e.nombre,
      id: e.id,
      conexion: Conexion.ble,
      protocolo: canal.protocolo,
      servicio: canal.servicio,
      caracteristica: canal.caracteristica,
      notificacion: canal.notificacion,
      sinRespuesta: canal.sinRespuesta,
    );
  }

  static Future<void> _conectarBle(String id) async {
    BleConnectionState estado;
    try {
      estado = await UniversalBle.getConnectionState(id);
    } catch (_) {
      estado = BleConnectionState.disconnected;
    }
    if (estado == BleConnectionState.connected) return;
    try {
      await UniversalBle.connect(id, timeout: const Duration(seconds: 15));
    } catch (_) {
      throw ErrorImpresora('No se pudo conectar con la impresora. Revisa que esté encendida, '
          'con papel y cerca del teléfono.');
    }
  }

  static Future<List<ServicioBle>> _serviciosBle(String id) async {
    await _conectarBle(id);
    final servicios = await UniversalBle.discoverServices(id);
    return [
      for (final s in servicios)
        ServicioBle(s.uuid, [
          for (final c in s.characteristics)
            CaracteristicaBle(
              c.uuid,
              escribe: c.properties.contains(CharacteristicProperty.write),
              escribeSinRespuesta: c.properties.contains(CharacteristicProperty.writeWithoutResponse),
              notifica: c.properties.contains(CharacteristicProperty.notify),
            ),
        ]),
    ];
  }

  /// Imprime el bitmap en la impresora guardada.
  static Future<void> imprimir(ImpresoraGuardada imp, BitmapMono bitmap) async {
    await _permisos();
    final bytes = imp.protocolo == Protocolo.gato ? trabajoGato(bitmap) : trabajoImpresion(bitmap);
    if (imp.conexion == Conexion.clasica) {
      await _imprimirClasica(imp.id, bytes);
    } else {
      await _imprimirBle(imp, bytes);
    }
  }

  static Future<void> _imprimirClasica(String mac, List<int> bytes) async {
    final yaConectada = _clasicaConectada == mac && await PrintBluetoothThermal.connectionStatus;
    if (!yaConectada) {
      if (await PrintBluetoothThermal.connectionStatus) await PrintBluetoothThermal.disconnect;
      final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac)
          .timeout(const Duration(seconds: 15), onTimeout: () => false);
      if (!ok) {
        _clasicaConectada = null;
        throw ErrorImpresora('No se pudo conectar con la impresora. Revisa que esté encendida, '
            'con papel y cerca del teléfono.');
      }
      _clasicaConectada = mac;
    }
    if (!await PrintBluetoothThermal.writeBytes(bytes)) {
      _clasicaConectada = null;
      throw ErrorImpresora('La impresora no recibió el sticker. Intenta de nuevo.');
    }
  }

  static Future<void> _imprimirBle(ImpresoraGuardada imp, List<int> bytes) async {
    final id = imp.id;
    final servicio = imp.servicio;
    final caracteristica = imp.caracteristica;
    if (servicio == null || caracteristica == null) {
      throw ErrorImpresora('Vuelve a elegir la impresora en Ajustes.');
    }
    await _conectarBle(id);
    try {
      await UniversalBle.discoverServices(id);
    } catch (_) {}

    var mtu = 23;
    try {
      mtu = await UniversalBle.requestMtu(id, 247);
    } catch (_) {}
    final tamano = (mtu - 3).clamp(20, 180);

    // Las mini impresoras piden pausa cuando se les llena la memoria.
    var pausada = false;
    StreamSubscription<Uint8List>? avisos;
    final notificacion = imp.notificacion;
    if (notificacion != null) {
      try {
        await UniversalBle.subscribeNotifications(id, servicio, notificacion);
        avisos = UniversalBle.characteristicValueStream(id, notificacion).listen((v) {
          final pausa = leerControlDeFlujo(v);
          if (pausa != null) pausada = pausa;
        });
      } catch (_) {}
    }

    try {
      for (var i = 0; i < bytes.length; i += tamano) {
        var esperas = 0;
        while (pausada && esperas < 100) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          esperas++;
        }
        final fin = (i + tamano) < bytes.length ? i + tamano : bytes.length;
        await UniversalBle.write(
          id,
          servicio,
          caracteristica,
          Uint8List.fromList(bytes.sublist(i, fin)),
          withoutResponse: imp.sinRespuesta,
        );
        // Pausa corta para no llenar la memoria de impresoras simples.
        if (imp.sinRespuesta) await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    } catch (e) {
      throw ErrorImpresora('Se cortó la conexión con la impresora mientras imprimía. Intenta de nuevo.');
    } finally {
      await avisos?.cancel();
    }
  }
}
