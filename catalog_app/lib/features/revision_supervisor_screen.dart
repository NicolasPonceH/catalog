import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../app_scope.dart';
import '../backup/respaldo.dart';
import '../data/base.dart';
import '../data/compra.dart';
import '../data/compras_repo.dart';
import '../data/fotos.dart';
import '../data/sesiones.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../reports/excel.dart';
import '../sync/wifi_sync.dart';
import '../system/notificaciones.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/escaner_vista.dart';
import '../widgets/guia.dart';
import 'ficha_screen.dart';
import 'traspaso.dart';

enum _FiltroRevision { todos, verificados, pendientes }

/// Módulo operativo de Revisión para el Supervisor (sin cambiar de sesión en la app):
/// - Escanea stickers con la cámara (QR o código de barras) o ingreso manual.
/// - Cruza los códigos leídos con los datos recibidos por Wi-Fi / archivo (o con
///   las compras locales si aún no se ha cargado un comprador externo).
/// - Marca qué piezas están verificadas físicamente y cuáles faltan.
/// - Permite abrir cada ficha completa (con foto y GPS) en modo solo lectura.
/// - Genera y comparte el Excel completo de la revisión con un toque.
class RevisionSupervisorScreen extends StatefulWidget {
  const RevisionSupervisorScreen({
    super.key,
    this.revisionInicial,
    this.iniciarConCamara = true,
  });

  final Sesion? revisionInicial;
  final bool iniciarConCamara;

  @override
  State<RevisionSupervisorScreen> createState() => _RevisionSupervisorScreenState();
}

class _RevisionSupervisorScreenState extends State<RevisionSupervisorScreen> {
  List<Sesion> _revisiones = const [];
  Sesion? _activa;
  CatalogDb? _baseExterna;
  List<Compra> _catalogo = const [];

  /// Código -> fecha/hora en que el supervisor lo escaneó con la cámara.
  Map<String, DateTime> _escaneados = {};

  bool _iniciado = false;
  bool _cargando = true;
  late bool _mostrarCamara = widget.iniciarConCamara;
  bool _exportando = false;
  _FiltroRevision _filtro = _FiltroRevision.todos;
  String? _ultimoAviso;
  bool _ultimoOk = true;

  final _gCamara = GlobalKey();
  final _gResumen = GlobalKey();
  final _gWifi = GlobalKey();
  final _gExcel = GlobalKey();
  final _gFiltros = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iniciado) {
      _iniciado = true;
      _inicializar();
    }
  }

  @override
  void dispose() {
    _cerrarBaseExterna();
    super.dispose();
  }

  Future<void> _cerrarBaseExterna() async {
    final b = _baseExterna;
    _baseExterna = null;
    if (b != null) {
      try {
        await b.cerrar();
      } catch (_) {}
    }
  }

  Future<void> _inicializar({Sesion? preferida}) async {
    if (!mounted) return;
    setState(() => _cargando = true);
    final scope = AppScope.of(context);
    final sesiones = scope.sesiones;
    final lista = (sesiones == null || !sesiones.documentos.existsSync())
        ? <Sesion>[]
        : (Directory(p.join(sesiones.documentos.path, 'sesiones')).existsSync()
            ? await sesiones.revisiones()
            : <Sesion>[]);
    Sesion? elegida = preferida ?? widget.revisionInicial;
    if (elegida != null) {
      elegida = lista.where((s) => s.id == elegida!.id).firstOrNull ?? elegida;
    } else if (lista.isNotEmpty) {
      elegida = lista.first;
    }
    await _cargarFuente(elegida, lista);
  }

  File _archivoVerificados(Sesion? rev, Directory respaldoDir) {
    if (rev != null) {
      return File(p.join(rev.carpeta.path, 'verificados_supervisor.json'));
    }
    return File(p.join(respaldoDir.path, 'verificados_supervisor_local.json'));
  }

  Future<void> _cargarFuente(Sesion? rev, List<Sesion> todas) async {
    await _cerrarBaseExterna();
    if (!mounted) return;
    final scope = AppScope.of(context);
    CatalogDb? nuevaBase;
    List<Compra> compras = const [];
    try {
      if (rev != null) {
        nuevaBase = await CatalogDb.abrir(ruta: rev.rutaBase);
        compras = await ComprasRepo(nuevaBase).comprasDelPeriodo(null);
      } else {
        compras = await scope.compras.comprasDelPeriodo(null);
      }
    } catch (_) {
      compras = const [];
    }

    final archivoVerif = _archivoVerificados(rev, scope.fotos.carpetaBase);
    final mapa = <String, DateTime>{};
    if (archivoVerif.existsSync()) {
      try {
        final crudo = jsonDecode(archivoVerif.readAsStringSync()) as Map<String, dynamic>;
        for (final e in crudo.entries) {
          final msVal = (e.value as num?)?.toInt();
          if (msVal != null) mapa[e.key] = DateTime.fromMillisecondsSinceEpoch(msVal);
        }
      } catch (_) {}
    }

    if (!mounted) {
      if (nuevaBase != null) await nuevaBase.cerrar();
      return;
    }
    setState(() {
      _revisiones = todas;
      _activa = rev;
      _baseExterna = nuevaBase;
      _catalogo = compras.reversed.toList();
      _escaneados = mapa;
      _cargando = false;
    });
  }

  Future<void> _guardarVerificados() async {
    final scope = AppScope.of(context);
    final f = _archivoVerificados(_activa, scope.fotos.carpetaBase);
    await f.parent.create(recursive: true);
    final jsonMapa = {
      for (final e in _escaneados.entries) e.key: e.value.millisecondsSinceEpoch,
    };
    await f.writeAsString(jsonEncode(jsonMapa), flush: true);
  }

  Future<void> _procesarLectura(String bruto) async {
    final codigo = leerCodigoEscaneado(bruto);
    if (codigo == null) {
      final d = AppScope.of(context).dispositivo;
      if (d?.vibrar ?? true) HapticFeedback.heavyImpact();
      setState(() {
        _ultimoAviso = tr('Ese código no tiene formato de sticker CataLog', 'That code is not a CataLog sticker format');
        _ultimoOk = false;
      });
      return;
    }

    final compra = _catalogo.where((c) => c.codigo == codigo).firstOrNull;
    final yaEstaba = _escaneados.containsKey(codigo);
    final d = AppScope.of(context).dispositivo;
    final vibrar = d?.vibrar ?? true;

    if (compra != null && compra.anulada) {
      if (vibrar) HapticFeedback.heavyImpact();
      setState(() {
        _ultimoAviso = tr('⚠ $codigo figura como COMPRA ANULADA', '⚠ $codigo is marked as VOIDED PURCHASE');
        _ultimoOk = false;
      });
      return;
    }

    final ahora = DateTime.now();
    _escaneados[codigo] = _escaneados[codigo] ?? ahora;
    await _guardarVerificados();
    if (!mounted) return;

    if (compra == null) {
      if (vibrar) HapticFeedback.mediumImpact();
      setState(() {
        _ultimoAviso = tr(
          'Código $codigo registrado en revisión (sin ficha previa cargada)',
          'Code $codigo logged in review (no prior record loaded)',
        );
        _ultimoOk = true;
      });
      return;
    }

    if (vibrar) HapticFeedback.mediumImpact();
    if (d?.sonar ?? true) SystemSound.play(SystemSoundType.click);
    if (!yaEstaba) {
      Notificaciones.avisarCataliticoEscaneado(
        d,
        codigo: codigo,
        detalle: '${tr('Verificado', 'Verified')} · ${compra.tipo} · ${clp(compra.precio)}',
      );
    }

    setState(() {
      _ultimoAviso = yaEstaba
          ? tr('✓ $codigo ya estaba verificado (${clp(compra.precio)})', '✓ $codigo was already verified (${clp(compra.precio)})')
          : tr('✅ Verificado $codigo · ${compra.tipo} · ${clp(compra.precio)}', '✅ Verified $codigo · ${compra.tipo} · ${clp(compra.precio)}');
      _ultimoOk = true;
    });
  }

  List<FilaRevisionExcel> _armarFilas() {
    final porCodigo = {for (final c in _catalogo) c.codigo: c};
    final resultado = <FilaRevisionExcel>[];

    // Primero los escaneados (el más reciente arriba)
    final codigosEscaneados = _escaneados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in codigosEscaneados) {
      resultado.add(FilaRevisionExcel(
        codigo: e.key,
        compra: porCodigo[e.key],
        escaneadoEn: e.value,
      ));
    }

    // Después los del catálogo que faltan por escanear
    for (final c in _catalogo) {
      if (!_escaneados.containsKey(c.codigo)) {
        resultado.add(FilaRevisionExcel(codigo: c.codigo, compra: c));
      }
    }
    return resultado;
  }

  Future<void> _exportarExcel() async {
    final filas = _armarFilas();
    if (filas.isEmpty) {
      avisar(
        context,
        tr(
          'Escanea al menos un catalítico o recibe compras por Wi-Fi para generar el Excel',
          'Scan at least one converter or receive purchases via Wi-Fi to generate the Excel',
        ),
      );
      return;
    }
    setState(() => _exportando = true);
    final comprasLocal = AppScope.of(context).compras;
    try {
      final comprador = _activa?.origen.isNotEmpty == true
          ? _activa!.origen
          : (await comprasLocal.leerAjuste('nombre') ?? '');
      final prefijo = _activa?.prefijo.isNotEmpty == true
          ? _activa!.prefijo
          : await comprasLocal.prefijo();
      final bytes = excelDeRevisionSupervisor(
        filas,
        comprador: comprador,
        prefijo: prefijo,
      );
      final hoy = fechaCorta(DateTime.now()).replaceAll('/', '-');
      await compartirExcel(
        bytes,
        'Revision-Supervisor-${prefijo.isEmpty ? 'CataLog' : prefijo}-$hoy.xlsx',
        texto: tr('Revisión de Supervisor · CataLog', 'Supervisor Review · CataLog'),
      );
    } catch (e) {
      if (mounted) avisar(context, '${tr('No se pudo crear el Excel', 'Could not create Excel')}: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<void> _sincronizarWifi({bool recibir = true}) async {
    final scope = AppScope.of(context);
    final contenido = await mostrarSincronizacionWifi(
      context,
      baseOrigen: _baseExterna ?? scope.base,
      carpetaOrigen: _activa?.carpeta ?? scope.fotos.carpetaBase,
      etiquetaOrigen: _activa?.nombre ?? tr('Revisión de Supervisor', 'Supervisor Review'),
      iniciarEnRecibir: recibir,
    );
    if (contenido == null || !mounted) return;
    await _aplicarRecibidoEnSupervisor(contenido);
  }

  Future<void> _importarZip() async {
    final bytes = await elegirArchivoCatalog(
      context,
      titulo: tr('Cargar compras para revisar', 'Load purchases to review'),
    );
    if (bytes == null || !mounted) return;
    try {
      final contenido = leerRespaldo(bytes);
      await _aplicarRecibidoEnSupervisor(contenido);
    } on RespaldoInvalido catch (e) {
      if (mounted) avisar(context, e.mensaje);
    }
  }

  Future<void> _aplicarRecibidoEnSupervisor(ContenidoRespaldo contenido) async {
    final sesiones = AppScope.of(context).sesiones;
    if (sesiones == null) return;
    await _cerrarBaseExterna();
    final guardada = await sesiones.guardarRevision(contenido);
    if (!mounted) return;
    await _inicializar(preferida: guardada);
    if (mounted) {
      avisar(
        context,
        tr(
          'Cargadas ${contenido.compras} compras listas para revisar con el escáner',
          'Loaded ${contenido.compras} purchases ready to scan & review',
        ),
      );
    }
  }

  Future<void> _abrirFichaSoloLectura(Compra c) async {
    final scopePadre = AppScope.of(context);
    final base = _baseExterna ?? scopePadre.base;
    final carpeta = _activa?.carpeta ?? scopePadre.fotos.carpetaBase;
    final sesionSoloLectura = _activa ??
        Sesion(
          id: 'supervisor_local',
          tipo: TipoSesion.revision,
          nombre: tr('Revisión de Supervisor', 'Supervisor Review'),
          rutaBase: base.db.path,
          carpeta: carpeta,
        );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppScope(
          base: base,
          fotos: FotosStore(carpeta),
          sesion: sesionSoloLectura,
          sesiones: scopePadre.sesiones,
          dispositivo: scopePadre.dispositivo,
          child: FichaScreen(id: c.id),
        ),
      ),
    );
  }

  Future<void> _reiniciarVerificados() async {
    if (_escaneados.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Reiniciar conteo de escaneos?', 'Reset scanned checkmarks?')),
        content: Text(
          tr(
            'Se desmarcan los catalíticos escaneados para empezar una nueva revisión física. Las compras no se borran.',
            'Clears scanned checkmarks so you can start a fresh physical count. Purchases are not deleted.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Reiniciar', 'Reset'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _escaneados.clear();
      _ultimoAviso = null;
    });
    await _guardarVerificados();
  }

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gWifi,
          icono: Icons.wifi,
          titulo: tr('Recibir o enviar por Wi-Fi', 'Receive or send over Wi-Fi'),
          texto: tr(
            'Recibe las compras del comprador en el mismo Wi-Fi (o envíale la revisión de vuelta) sin cambiar de sesión ni mezclar datos.',
            'Receive the buyer’s purchases over the same Wi-Fi (or send data back) without switching sessions or mixing data.',
          ),
        ),
        if (_mostrarCamara)
          PasoGuia(
            clave: _gCamara,
            icono: Icons.qr_code_scanner,
            titulo: tr('Escáner de revisión', 'Review scanner'),
            texto: tr(
              'Apunta a cada sticker físico: el módulo lee el QR o código de barras, verifica su precio y foto, y lo marca como cuadrado.',
              'Point at each physical sticker: reads the QR or barcode, verifies its price and photo, and marks it as checked.',
            ),
          ),
        PasoGuia(
          clave: _gResumen,
          icono: Icons.fact_check_outlined,
          titulo: tr('Avance y Excel', 'Progress & Excel'),
          texto: tr(
            'Mira cuántos catalíticos van verificados, cuántos faltan y toca "Excel" para exportar la planilla completa.',
            'See how many converters are verified vs. missing, and tap "Excel" to export the full spreadsheet.',
          ),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final todasFilas = _armarFilas();
    final verificadasCount = todasFilas.where((f) => f.verificado).length;
    final pendientesCount = todasFilas.where((f) => !f.verificado && f.compra != null && !f.compra!.anulada).length;
    final montoVerificado = todasFilas
        .where((f) => f.verificado && f.compra != null && !f.compra!.anulada)
        .fold<int>(0, (s, f) => s + f.compra!.precio);

    final visibles = switch (_filtro) {
      _FiltroRevision.todos => todasFilas,
      _FiltroRevision.verificados => todasFilas.where((f) => f.verificado).toList(),
      _FiltroRevision.pendientes => todasFilas.where((f) => !f.verificado && !(f.compra?.anulada ?? false)).toList(),
    };

    final origenTexto = _activa != null
        ? '${_activa!.nombre}${_activa!.prefijo.isNotEmpty ? ' (${_activa!.prefijo})' : ''}'
        : tr('Catálogo local de este equipo', 'Local catalog on this phone');

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(tr('Revisión de Supervisor', 'Supervisor Review')),
        ),
        actions: [
          IconButton(
            key: _gWifi,
            tooltip: tr('Sincronizar por Wi-Fi', 'Wi-Fi Sync'),
            icon: const Icon(Icons.wifi_tethering),
            onPressed: () => _sincronizarWifi(recibir: true),
          ),
          IconButton(
            tooltip: _mostrarCamara ? tr('Ocultar cámara', 'Hide camera') : tr('Mostrar cámara', 'Show camera'),
            icon: Icon(_mostrarCamara ? Icons.videocam_off_outlined : Icons.qr_code_scanner),
            onPressed: () => setState(() => _mostrarCamara = !_mostrarCamara),
          ),
          PopupMenuButton<String>(
            onSelected: (accion) async {
              switch (accion) {
                case 'wifi_enviar':
                  await _sincronizarWifi(recibir: false);
                case 'zip':
                  await _importarZip();
                case 'local':
                  await _cargarFuente(null, _revisiones);
                case 'reiniciar':
                  await _reiniciarVerificados();
                default:
                  if (accion.startsWith('rev:')) {
                    final id = accion.substring(4);
                    final s = _revisiones.where((r) => r.id == id).firstOrNull;
                    if (s != null) await _cargarFuente(s, _revisiones);
                  }
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'wifi_enviar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(tr('Enviar estos datos por Wi-Fi', 'Send this data over Wi-Fi')),
                ),
              ),
              PopupMenuItem(
                value: 'zip',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(tr('Cargar archivo .zip recibido', 'Load received .zip file')),
                ),
              ),
              PopupMenuItem(
                value: 'reiniciar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: Text(tr('Reiniciar conteo escaneado', 'Reset scanned count')),
                ),
              ),
              if (_revisiones.isNotEmpty) const PopupMenuDivider(),
              for (final r in _revisiones)
                PopupMenuItem(
                  value: 'rev:${r.id}',
                  child: Row(
                    children: [
                      Icon(
                        _activa?.id == r.id ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                        color: CatalogColors.naranja,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.nombre, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              if (_activa != null)
                PopupMenuItem(
                  value: 'local',
                  child: Text(tr('Revisar compras de este celular', 'Review this phone’s own purchases')),
                ),
            ],
          ),
          BotonAyuda(alTocar: _mostrarGuia),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mostrarCamara)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: SizedBox(
                        key: _gCamara,
                        height: 176,
                        child: Stack(
                          children: [
                            Positioned.fill(child: EscanerVista(alLeer: _procesarLectura)),
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                onPressed: () async {
                                  final t = await pedirCodigoManual(context);
                                  if (t != null && t.trim().isNotEmpty) await _procesarLectura(t);
                                },
                                icon: const Icon(Icons.keyboard_outlined, size: 17),
                                label: Text(tr('Código a mano', 'Manual code'), style: const TextStyle(fontSize: 12.5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_ultimoAviso != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: (_ultimoOk ? CatalogColors.verde : CatalogColors.rojo).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _ultimoOk ? CatalogColors.verde : CatalogColors.rojo),
                        ),
                        child: Text(
                          _ultimoAviso!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _ultimoOk ? CatalogColors.verde : CatalogColors.rojo,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Container(
                      key: _gResumen,
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: CatalogColors.marino,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  origenTexto,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 12.5),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    clp(montoVerificado),
                                    style: mono(size: 23, color: CatalogColors.naranja),
                                  ),
                                ),
                                Text(
                                  tr(
                                    '$verificadasCount verificados · $pendientesCount pendientes',
                                    '$verificadasCount verified · $pendientesCount pending',
                                  ),
                                  style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            key: _gExcel,
                            style: FilledButton.styleFrom(
                              backgroundColor: CatalogColors.naranja,
                              foregroundColor: CatalogColors.marino,
                              minimumSize: const Size(0, 42),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: _exportando ? null : _exportarExcel,
                            icon: _exportando
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.table_view_outlined, size: 19),
                            label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    key: _gFiltros,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text('${tr('Todos', 'All')} (${todasFilas.length})'),
                          selected: _filtro == _FiltroRevision.todos,
                          onSelected: (_) => setState(() => _filtro = _FiltroRevision.todos),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('${tr('Verificados', 'Verified')} ($verificadasCount)'),
                          selected: _filtro == _FiltroRevision.verificados,
                          onSelected: (_) => setState(() => _filtro = _FiltroRevision.verificados),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: Text('${tr('Pendientes', 'Pending')} ($pendientesCount)'),
                          selected: _filtro == _FiltroRevision.pendientes,
                          onSelected: (_) => setState(() => _filtro = _FiltroRevision.pendientes),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: visibles.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.qr_code_scanner, size: 38, color: CatalogColors.naranja),
                                      const SizedBox(height: 8),
                                      Text(
                                        todasFilas.isEmpty
                                            ? tr(
                                                'Apunta la cámara a los stickers de los catalíticos o toca el ícono Wi-Fi arriba para recibir las compras del comprador.',
                                                'Point the camera at converter stickers or tap the Wi-Fi icon above to receive the buyer’s purchases.',
                                              )
                                            : tr('No hay elementos en este filtro.', 'No items match this filter.'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 14.5, height: 1.4, color: CatalogColors.acero),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                            itemCount: visibles.length,
                            itemBuilder: (ctx, i) {
                              final item = visibles[i];
                              final c = item.compra;
                              final verif = item.verificado;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: verif
                                          ? CatalogColors.verde.withValues(alpha: 0.7)
                                          : CatalogColors.naranja.withValues(alpha: 0.75),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: c != null ? () => _abrirFichaSoloLectura(c) : null,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                      child: Row(
                                        children: [
                                          if (c != null)
                                            MarcaTipo(material: c.material, anulada: c.anulada)
                                          else
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: CatalogColors.verde,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: const Icon(Icons.qr_code, color: Colors.white, size: 20),
                                            ),
                                          const SizedBox(width: 11),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        item.codigo,
                                                        style: mono(size: 13),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (c != null)
                                                      Text(clp(c.precio), style: mono(size: 14.5)),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  c != null
                                                      ? '${c.vendedor}${c.autos.isNotEmpty ? ' · ${c.autos}' : ''}'
                                                      : tr('Código escaneado directo', 'Directly scanned code'),
                                                  style: etiqueta,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(
                                                      verif ? Icons.check_circle : Icons.schedule,
                                                      size: 14,
                                                      color: verif ? CatalogColors.verde : CatalogColors.naranja,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        verif
                                                            ? '${tr('Verificado', 'Verified')} · ${fechaHora(item.escaneadoEn!)}'
                                                            : tr('Falta escanear sticker', 'Sticker not scanned yet'),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: verif ? CatalogColors.verde : CatalogColors.naranja,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
