import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../backup/respaldo.dart';
import '../data/base.dart';
import '../data/compras_repo.dart';
import '../i18n.dart';
import '../system/sistema.dart';
import '../theme.dart';
import '../widgets/escaner_vista.dart';
import '../widgets/qr_vista.dart';

/// Puerto UDP de autodescubrimiento en la misma red Wi-Fi local.
const int puertoAnuncioWifi = 48791;
const String prefijoQrWifi = 'CATALOG-WIFI|';

/// Datos de conexión codificados en el QR o anunciados por UDP en la red Wi-Fi.
class PuntoWifiCatalog {
  const PuntoWifiCatalog({
    required this.ip,
    required this.puerto,
    required this.token,
    required this.nombre,
    required this.prefijo,
    required this.compras,
    this.conFotos = true,
  });

  final String ip;
  final int puerto;
  final String token;
  final String nombre;
  final String prefijo;
  final int compras;
  final bool conFotos;

  String aQr() => '$prefijoQrWifi$ip|$puerto|$token|${Uri.encodeComponent(nombre)}|$prefijo|$compras|${conFotos ? 1 : 0}';

  static PuntoWifiCatalog? deQr(String texto) {
    final limpio = texto.trim();
    if (!limpio.startsWith(prefijoQrWifi)) return null;
    final partes = limpio.substring(prefijoQrWifi.length).split('|');
    if (partes.length < 3) return null;
    final ip = partes[0].trim();
    final puerto = int.tryParse(partes[1].trim());
    final token = partes[2].trim();
    if (ip.isEmpty || puerto == null || puerto <= 0 || puerto > 65535 || token.isEmpty) return null;
    final nombre = partes.length > 3 ? Uri.decodeComponent(partes[3]) : '';
    final prefijo = partes.length > 4 ? partes[4] : '';
    final compras = partes.length > 5 ? (int.tryParse(partes[5]) ?? 0) : 0;
    final conFotos = partes.length > 6 ? partes[6] == '1' : true;
    return PuntoWifiCatalog(
      ip: ip,
      puerto: puerto,
      token: token,
      nombre: nombre,
      prefijo: prefijo,
      compras: compras,
      conFotos: conFotos,
    );
  }

  String aJsonUdp() => jsonEncode({
        'app': 'CataLogWifi',
        'ip': ip,
        'puerto': puerto,
        'token': token,
        'nombre': nombre,
        'prefijo': prefijo,
        'compras': compras,
        'conFotos': conFotos,
      });

  static PuntoWifiCatalog? deJsonUdp(String s, {String? ipRemitente}) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['app'] != 'CataLogWifi') return null;
      final ip = (m['ip'] as String?)?.trim().isNotEmpty == true ? (m['ip'] as String).trim() : (ipRemitente ?? '');
      final puerto = (m['puerto'] as num?)?.toInt();
      final token = (m['token'] as String?)?.trim() ?? '';
      if (ip.isEmpty || puerto == null || token.isEmpty) return null;
      return PuntoWifiCatalog(
        ip: ip,
        puerto: puerto,
        token: token,
        nombre: m['nombre'] as String? ?? '',
        prefijo: m['prefijo'] as String? ?? '',
        compras: (m['compras'] as num?)?.toInt() ?? 0,
        conFotos: m['conFotos'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Descubre la IPv4 local (192.168.x.x / 10.x.x.x / 172.16-31.x.x) del teléfono.
Future<String?> detectarIpWifiLocal() async {
  final nativa = await Sistema.obtenerIpLocal();
  if (nativa != null && nativa.isNotEmpty && !nativa.startsWith('127.')) return nativa;
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
    String? candidata;
    for (final iface in interfaces) {
      final nom = iface.name.toLowerCase();
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (addr.isLoopback || ip.startsWith('127.')) continue;
        final privada = ip.startsWith('192.168.') || ip.startsWith('10.') || ip.startsWith('172.');
        if (privada && (nom.contains('wlan') || nom.contains('wifi') || nom.contains('ap') || nom.contains('eth'))) {
          return ip;
        }
        if (privada) candidata ??= ip;
      }
    }
    return candidata;
  } catch (_) {
    return null;
  }
}

/// Servidor TCP efímero en red local que entrega un paquete `.zip` de CataLog
/// solo a quien presente el token válido (y opcionalmente se anuncia por UDP).
class ServidorWifiCatalog {
  ServidorWifiCatalog._({
    required this.servidor,
    required this.punto,
    required Future<Uint8List> Function() generarZip,
    this.alTransferir,
  }) {
    _generarZip = generarZip;
  }

  final ServerSocket servidor;
  final PuntoWifiCatalog punto;
  late final Future<Uint8List> Function() _generarZip;
  final VoidCallback? alTransferir;

  RawDatagramSocket? _udp;
  Timer? _timerAnuncio;
  StreamSubscription<Socket>? _sub;
  Uint8List? _cacheZip;
  int transferencias = 0;

  static String _generarToken() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  static Future<ServidorWifiCatalog> iniciar({
    required String ip,
    required String nombre,
    required String prefijo,
    required int compras,
    required bool conFotos,
    required Future<Uint8List> Function() generarZip,
    int puerto = 0,
    bool anunciarUdp = true,
    VoidCallback? alTransferir,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, puerto);
    final token = _generarToken();
    final punto = PuntoWifiCatalog(
      ip: ip,
      puerto: server.port,
      token: token,
      nombre: nombre,
      prefijo: prefijo,
      compras: compras,
      conFotos: conFotos,
    );
    final inst = ServidorWifiCatalog._(
      servidor: server,
      punto: punto,
      generarZip: generarZip,
      alTransferir: alTransferir,
    );
    inst._escuchar();
    if (anunciarUdp) await inst._iniciarAnuncioUdp();
    return inst;
  }

  void _escuchar() {
    _sub = servidor.listen((cliente) async {
      try {
        cliente.setOption(SocketOption.tcpNoDelay, true);
        final linea = await utf8.decoder
            .bind(cliente)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 8));
        final pedido = jsonDecode(linea) as Map<String, dynamic>;
        if (pedido['token'] != punto.token) {
          cliente.add(utf8.encode('${jsonEncode({'ok': false, 'error': 'Código inválido'})}\n'));
          await cliente.flush();
          await cliente.close();
          return;
        }
        final zip = _cacheZip ??= await _generarZip();
        final cabecera = '${jsonEncode({'ok': true, 'tamano': zip.length})}\n';
        cliente.add(utf8.encode(cabecera));
        cliente.add(zip);
        await cliente.flush();
        transferencias++;
        alTransferir?.call();
      } catch (_) {
      } finally {
        try {
          await cliente.close();
        } catch (_) {}
      }
    });
  }

  Future<void> _iniciarAnuncioUdp() async {
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udp.broadcastEnabled = true;
      _udp = udp;
      final datos = utf8.encode(punto.aJsonUdp());
      final partesIp = punto.ip.split('.');
      final broadcastSubred = partesIp.length == 4 ? '${partesIp[0]}.${partesIp[1]}.${partesIp[2]}.255' : null;

      void emitir() {
        try {
          udp.send(datos, InternetAddress('255.255.255.255'), puertoAnuncioWifi);
          if (broadcastSubred != null) {
            udp.send(datos, InternetAddress(broadcastSubred), puertoAnuncioWifi);
          }
        } catch (_) {}
      }

      emitir();
      _timerAnuncio = Timer.periodic(const Duration(milliseconds: 1400), (_) => emitir());
    } catch (_) {}
  }

  Future<void> cerrar() async {
    _timerAnuncio?.cancel();
    _udp?.close();
    await _sub?.cancel();
    try {
      await servidor.close();
    } catch (_) {}
  }
}

/// Descarga el respaldo `.zip` desde otro celular con CataLog en la misma red Wi-Fi.
Future<Uint8List> descargarPorWifi(
  PuntoWifiCatalog punto, {
  void Function(double progreso)? alAvanzar,
}) async {
  final socket = await Socket.connect(
    punto.ip,
    punto.puerto,
    timeout: const Duration(seconds: 7),
  );
  try {
    socket.setOption(SocketOption.tcpNoDelay, true);
    socket.add(utf8.encode('${jsonEncode({'token': punto.token})}\n'));
    await socket.flush();

    final constructor = BytesBuilder(copy: false);
    var cabeceraLeida = false;
    var tamanoEsperado = 0;
    final completer = Completer<Uint8List>();

    late StreamSubscription<Uint8List> sub;
    sub = socket.listen(
      (chunk) {
        constructor.add(chunk);
        if (!cabeceraLeida) {
          final actual = constructor.toBytes();
          final salto = actual.indexOf(10); // '\n'
          if (salto != -1) {
            final cabTexto = utf8.decode(actual.sublist(0, salto));
            final resp = jsonDecode(cabTexto) as Map<String, dynamic>;
            if (resp['ok'] != true) {
              if (!completer.isCompleted) {
                completer.completeError(Exception(resp['error'] ?? 'Conexión rechazada'));
              }
              sub.cancel();
              return;
            }
            tamanoEsperado = (resp['tamano'] as num).toInt();
            cabeceraLeida = true;
            final resto = actual.sublist(salto + 1);
            constructor.clear();
            constructor.add(resto);
          }
        }
        if (cabeceraLeida) {
          if (tamanoEsperado > 0 && alAvanzar != null) {
            alAvanzar((constructor.length / tamanoEsperado).clamp(0.0, 1.0));
          }
          if (constructor.length >= tamanoEsperado) {
            final todo = constructor.takeBytes();
            if (!completer.isCompleted) {
              completer.complete(Uint8List.sublistView(todo, 0, tamanoEsperado));
            }
            sub.cancel();
          }
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          if (cabeceraLeida && constructor.length >= tamanoEsperado) {
            completer.complete(Uint8List.sublistView(constructor.takeBytes(), 0, tamanoEsperado));
          } else {
            completer.completeError(Exception('La transferencia se cortó antes de terminar'));
          }
        }
      },
    );

    return await completer.future.timeout(const Duration(seconds: 45));
  } finally {
    try {
      socket.destroy();
    } catch (_) {}
  }
}

/// Pantalla modal para enviar o recibir datos en el mismo Wi-Fi (Comprador ⇄ Supervisor).
/// Si [origenPersonalizado] se pasa (p. ej. desde el Módulo de Revisión del Supervisor),
/// permite enviar esa base en sentido inverso (Supervisor → Comprador).
Future<ContenidoRespaldo?> mostrarSincronizacionWifi(
  BuildContext context, {
  CatalogDb? baseOrigen,
  Directory? carpetaOrigen,
  String? etiquetaOrigen,
  bool iniciarEnRecibir = false,
}) async {
  return Navigator.of(context).push<ContenidoRespaldo>(
    MaterialPageRoute(
      builder: (_) => _WifiSyncScreen(
        baseOrigen: baseOrigen,
        carpetaOrigen: carpetaOrigen,
        etiquetaOrigen: etiquetaOrigen,
        iniciarEnRecibir: iniciarEnRecibir,
      ),
    ),
  );
}

class _WifiSyncScreen extends StatefulWidget {
  const _WifiSyncScreen({
    this.baseOrigen,
    this.carpetaOrigen,
    this.etiquetaOrigen,
    this.iniciarEnRecibir = false,
  });

  final CatalogDb? baseOrigen;
  final Directory? carpetaOrigen;
  final String? etiquetaOrigen;
  final bool iniciarEnRecibir;

  @override
  State<_WifiSyncScreen> createState() => _WifiSyncScreenState();
}

class _WifiSyncScreenState extends State<_WifiSyncScreen> {
  late bool _modoRecibir = widget.iniciarEnRecibir;
  bool _conFotos = true;
  bool _preparando = true;
  String? _errorRed;
  ServidorWifiCatalog? _servidor;
  int _enviados = 0;

  // Para recibir: autodescubrimiento UDP + escáner QR + manual.
  RawDatagramSocket? _escuchaUdp;
  final Map<String, (PuntoWifiCatalog, DateTime)> _detectados = {};
  Timer? _limpiadorUdp;
  bool _descargando = false;
  double _progreso = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _actualizarModo());
  }

  @override
  void dispose() {
    _detenerTodo();
    super.dispose();
  }

  Future<void> _detenerTodo() async {
    _limpiadorUdp?.cancel();
    _limpiadorUdp = null;
    _escuchaUdp?.close();
    _escuchaUdp = null;
    final srv = _servidor;
    _servidor = null;
    if (srv != null) await srv.cerrar();
  }

  Future<void> _actualizarModo() async {
    await _detenerTodo();
    if (!mounted) return;
    if (_modoRecibir) {
      setState(() {
        _preparando = false;
        _errorRed = null;
        _detectados.clear();
      });
      await _iniciarEscuchaUdp();
    } else {
      await _iniciarServidor();
    }
  }

  Future<void> _iniciarServidor() async {
    setState(() {
      _preparando = true;
      _errorRed = null;
    });
    final scope = AppScope.of(context);
    final base = widget.baseOrigen ?? scope.base;
    final carpeta = widget.carpetaOrigen ?? scope.fotos.carpetaBase;
    final ip = await detectarIpWifiLocal();
    if (!mounted) return;
    if (ip == null) {
      setState(() {
        _preparando = false;
        _errorRed = tr(
          'Conéctate a una red Wi-Fi o activa la Zona Wi-Fi (Hotspot) en uno de los celulares y toca Reintentar.',
          'Connect to a Wi-Fi network or turn on Personal Hotspot on one of the phones, then tap Retry.',
        );
      });
      return;
    }
    try {
      final repo = ComprasRepo(base);
      final total = await repo.contarCompras();
      final pref = await repo.prefijo();
      final nom = widget.etiquetaOrigen ?? (await repo.leerAjuste('nombre') ?? '');
      final conFotos = _conFotos;
      final srv = await ServidorWifiCatalog.iniciar(
        ip: ip,
        nombre: nom,
        prefijo: pref,
        compras: total,
        conFotos: conFotos,
        generarZip: () => armarRespaldo(base, carpeta, incluirFotos: conFotos, tipo: 'wifi'),
        alTransferir: () {
          if (mounted) {
            setState(() => _enviados++);
            avisar(context, tr('¡Datos enviados por Wi-Fi con éxito!', 'Data sent over Wi-Fi!'));
          }
        },
      );
      if (!mounted) {
        await srv.cerrar();
        return;
      }
      setState(() {
        _servidor = srv;
        _preparando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparando = false;
        _errorRed = '${tr('No se pudo abrir la conexión local', 'Could not open local connection')}: $e';
      });
    }
  }

  Future<void> _iniciarEscuchaUdp() async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puertoAnuncioWifi, reuseAddress: true);
      _escuchaUdp = socket;
      socket.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = socket.receive();
        if (dg == null) return;
        final pto = PuntoWifiCatalog.deJsonUdp(
          utf8.decode(dg.data, allowMalformed: true),
          ipRemitente: dg.address.address,
        );
        if (pto != null && mounted) {
          setState(() {
            _detectados['${pto.ip}:${pto.puerto}'] = (pto, DateTime.now());
          });
        }
      });
      _limpiadorUdp = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!mounted) return;
        final ahora = DateTime.now();
        setState(() {
          _detectados.removeWhere((_, v) => ahora.difference(v.$2) > const Duration(seconds: 6));
        });
      });
    } catch (_) {}
  }

  Future<void> _conectarYPoblar(PuntoWifiCatalog punto) async {
    if (_descargando) return;
    setState(() {
      _descargando = true;
      _progreso = 0;
    });
    try {
      final bytes = await descargarPorWifi(
        punto,
        alAvanzar: (p) {
          if (mounted) setState(() => _progreso = p);
        },
      );
      final contenido = leerRespaldo(bytes);
      if (!mounted) return;
      Navigator.of(context).pop(contenido);
    } catch (e) {
      if (!mounted) return;
      setState(() => _descargando = false);
      avisar(
        context,
        '${tr('No se pudo recibir por Wi-Fi. Verifica que ambos celulares estén en el mismo Wi-Fi', 'Could not receive over Wi-Fi. Make sure both phones are on the same Wi-Fi')}: $e',
      );
    }
  }

  Future<void> _conectarManual() async {
    final ipCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Conexión manual por Wi-Fi', 'Manual Wi-Fi connection')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: tr('Dirección (IP:Puerto)', 'Address (IP:Port)'),
                hintText: '192.168.1.45:42100',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tokenCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Clave de 6 dígitos', '6-digit PIN'),
                hintText: '123456',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Conectar', 'Connect'))),
        ],
      ),
    );
    final dir = ipCtrl.text.trim();
    final tok = tokenCtrl.text.trim();
    ipCtrl.dispose();
    tokenCtrl.dispose();
    if (ok != true || !mounted) return;
    final partes = dir.split(':');
    if (partes.length != 2 || int.tryParse(partes[1]) == null || tok.isEmpty) {
      avisar(context, tr('Revisa la IP:Puerto y la clave de 6 dígitos', 'Check IP:Port and 6-digit PIN'));
      return;
    }
    await _conectarYPoblar(PuntoWifiCatalog(
      ip: partes[0].trim(),
      puerto: int.parse(partes[1].trim()),
      token: tok,
      nombre: '',
      prefijo: '',
      compras: 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Sincronizar por Wi-Fi', 'Wi-Fi Sync')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(tr('Enviar (Mostrar QR)', 'Send (Show QR)')),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.wifi_find),
                  label: Text(tr('Recibir datos', 'Receive data')),
                ),
              ],
              selected: {_modoRecibir},
              showSelectedIcon: false,
              onSelectionChanged: _descargando
                  ? null
                  : (s) {
                      setState(() => _modoRecibir = s.first);
                      _actualizarModo();
                    },
            ),
            const SizedBox(height: 14),
            if (!_modoRecibir) _vistaEnviar() else _vistaRecibir(),
          ],
        ),
      ),
    );
  }

  Widget _vistaEnviar() {
    if (_preparando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorRed != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Icon(Icons.wifi_off, size: 42, color: CatalogColors.rojo),
              const SizedBox(height: 10),
              Text(_errorRed!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _iniciarServidor,
                icon: const Icon(Icons.refresh),
                label: Text(tr('Reintentar', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }
    final srv = _servidor!;
    final p = srv.punto;
    final qr = p.aQr();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: CatalogColors.naranja, width: 1.6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Text(
                  widget.etiquetaOrigen != null
                      ? tr('Enviando: ${widget.etiquetaOrigen}', 'Sending: ${widget.etiquetaOrigen}')
                      : tr('Listo para enviar tus compras', 'Ready to send your purchases'),
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    'En el otro celular (en el mismo Wi-Fi o zona portátil), abre Sincronizar por Wi-Fi > Recibir datos: aparecerá solo o escanea este QR.',
                    'On the other phone (on the same Wi-Fi or hotspot), open Wi-Fi Sync > Receive data: it will appear automatically or scan this QR.',
                  ),
                  textAlign: TextAlign.center,
                  style: etiqueta.copyWith(height: 1.35),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: CatalogColors.borde),
                  ),
                  child: QrVista(key: ValueKey(qr), datos: qr, tamano: 196),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: CatalogColors.marino,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${p.ip}:${p.puerto}',
                        style: mono(size: 14, color: Colors.white),
                      ),
                      Text(
                        '${tr('Clave', 'PIN')}: ${p.token}',
                        style: mono(size: 16, weight: FontWeight.w700, color: CatalogColors.naranja),
                      ),
                    ],
                  ),
                ),
                if (_enviados > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: CatalogColors.verde, size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tr('Transferido $_enviados ${_enviados == 1 ? 'vez' : 'veces'}', 'Transferred $_enviados time(s)'),
                          style: TextStyle(color: CatalogColors.verde, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: SwitchListTile(
            title: Text(tr('Incluir fotos de los catalíticos', 'Include converter photos')),
            subtitle: Text(
              _conFotos
                  ? tr('Pasa compras y fotos completas por Wi-Fi', 'Transfers purchases and all photos over Wi-Fi')
                  : tr('Solo datos y códigos (instantáneo)', 'Data and codes only (instant)'),
              style: etiqueta,
            ),
            value: _conFotos,
            onChanged: (v) {
              setState(() => _conFotos = v);
              _iniciarServidor();
            },
          ),
        ),
      ],
    );
  }

  Widget _vistaRecibir() {
    if (_descargando) {
      final pct = (_progreso * 100).round();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(
                tr('Recibiendo datos por Wi-Fi… $pct%', 'Receiving data over Wi-Fi… $pct%'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: _progreso > 0 ? _progreso : null),
            ],
          ),
        ),
      );
    }

    final equipos = _detectados.values.map((e) => e.$1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (equipos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              tr('Celulares detectados en este Wi-Fi', 'Phones detected on this Wi-Fi'),
              style: etiqueta.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final eq in equipos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: CatalogColors.naranja, width: 1.8),
                ),
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: CatalogColors.naranja,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.smartphone, color: CatalogColors.marino),
                  ),
                  title: Text(
                    eq.nombre.isNotEmpty
                        ? eq.nombre
                        : (eq.prefijo.isNotEmpty ? 'CataLog (${eq.prefijo})' : eq.ip),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${eq.compras} ${tr('compras', 'purchases')} · ${eq.conFotos ? tr('con fotos', 'with photos') : tr('sin fotos', 'no photos')}',
                    style: etiqueta,
                  ),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(88, 38)),
                    onPressed: () => _conectarYPoblar(eq),
                    child: Text(tr('Recibir', 'Receive')),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          'Buscando celulares en el mismo Wi-Fi… O apunta abajo al código QR del otro teléfono.',
                          'Searching for phones on the same Wi-Fi… Or point below at the other phone’s QR code.',
                        ),
                        style: etiqueta.copyWith(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        SizedBox(
          height: 250,
          child: EscanerVista(
            alLeer: (texto) {
              final pto = PuntoWifiCatalog.deQr(texto);
              if (pto == null) {
                avisar(context, tr('Apunta al QR de conexión Wi-Fi de CataLog', 'Point at CataLog’s Wi-Fi QR code'));
                return;
              }
              _conectarYPoblar(pto);
            },
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _conectarManual,
          icon: const Icon(Icons.dialpad),
          label: Text(tr('Ingresar IP y clave a mano', 'Enter IP & PIN manually')),
        ),
      ],
    );
  }
}
