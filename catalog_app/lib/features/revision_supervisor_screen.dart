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
import '../data/supervisor_repo.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import '../printing/etiqueta.dart';
import '../printing/imprimir.dart';
import '../reports/excel.dart';
import '../sync/wifi_sync.dart';
import '../system/confirmar.dart';
import '../system/notificaciones.dart';
import '../theme.dart';
import '../widgets/compra_tile.dart';
import '../widgets/escaner_vista.dart';
import '../widgets/guia.dart';
import 'ficha_screen.dart';
import 'traspaso.dart';

enum _FiltroRevision { todos, pendientes, verificados, observados }
enum _VistaSupervisor { activa, lotes }

/// Módulo rediseñado de Revisión de Supervisor (v1.7):
/// - Panel ejecutivo con anillo de avance en tiempo real, montos cuadrados y faltantes.
/// - Agrupación automática por fecha de compra + filtro rápido por día o rango de fechas.
/// - Vista previa con miniatura de foto, código grabado y estado de llenado de la cerámica.
/// - Botón de Observación / Discrepancia de 1 toque (destacado en rojo en la app y en el Excel).
/// - Guardado como Lote de Supervisor: impide repetir en revisiones futuras un catalítico ya contado.
/// - Impresión de Etiqueta Maestra QR del Saco / Caja y exportación a Excel con logo y Tablas Dinámicas.
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

  /// Código -> fecha/hora en que el supervisor lo escaneó con la cámara en la sesión actual.
  Map<String, DateTime> _escaneados = {};

  /// Código -> observación / discrepancia marcada por el supervisor en la sesión actual.
  Map<String, ObservacionSupervisor> _observaciones = {};

  /// Catalíticos que ya fueron cerrados en algún Lote de Supervisor previo (no se repiten).
  Map<String, PrevioLoteSupervisor> _yaEnLotes = {};

  /// Historial de Lotes de Supervisor guardados en este teléfono.
  List<LoteSupervisor> _lotesGuardados = const [];

  _VistaSupervisor _vista = _VistaSupervisor.activa;
  _FiltroRevision _filtro = _FiltroRevision.todos;
  DateTimeRange? _filtroFechas;
  bool _mostrarYaRevisados = false;

  bool _iniciado = false;
  bool _cargando = true;
  late bool _mostrarCamara = widget.iniciarConCamara;
  bool _exportando = false;

  String? _ultimoAviso;
  bool _ultimoOk = true;
  Compra? _ultimaCompraEscaneada;

  final _gCamara = GlobalKey();
  final _gResumen = GlobalKey();
  final _gWifi = GlobalKey();
  final _gExcel = GlobalKey();

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

  Directory get _carpetaFotosActiva => _activa?.carpeta ?? AppScope.of(context).fotos.carpetaBase;

  File _archivoEstadoBorrador(Sesion? rev, Directory respaldoDir) {
    if (rev != null) {
      return File(p.join(rev.carpeta.path, 'verificados_supervisor_v2.json'));
    }
    return File(p.join(respaldoDir.path, 'verificados_supervisor_local_v2.json'));
  }

  File _archivoLegado(Sesion? rev, Directory respaldoDir) {
    if (rev != null) {
      return File(p.join(rev.carpeta.path, 'verificados_supervisor.json'));
    }
    return File(p.join(respaldoDir.path, 'verificados_supervisor_local.json'));
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

  Future<void> _refrescarLotesSupervisor() async {
    final sup = AppScope.of(context).supervisor;
    final ya = await sup.mapaYaRevisados();
    final lotes = await sup.listarLotes();
    if (!mounted) return;
    setState(() {
      _yaEnLotes = ya;
      _lotesGuardados = lotes;
    });
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

    final yaEnLotes = await scope.supervisor.mapaYaRevisados();
    final lotesGuardados = await scope.supervisor.listarLotes();

    final mapaEsc = <String, DateTime>{};
    final mapaObs = <String, ObservacionSupervisor>{};
    final archivoV2 = _archivoEstadoBorrador(rev, scope.fotos.carpetaBase);
    final archivoV1 = _archivoLegado(rev, scope.fotos.carpetaBase);

    if (archivoV2.existsSync()) {
      try {
        final crudo = jsonDecode(archivoV2.readAsStringSync()) as Map<String, dynamic>;
        final esc = crudo['escaneados'] as Map<String, dynamic>? ?? const {};
        for (final e in esc.entries) {
          final msVal = (e.value as num?)?.toInt();
          if (msVal != null && !yaEnLotes.containsKey(e.key)) {
            mapaEsc[e.key] = DateTime.fromMillisecondsSinceEpoch(msVal);
          }
        }
        final obs = crudo['observaciones'] as Map<String, dynamic>? ?? const {};
        for (final e in obs.entries) {
          if (e.value is Map<String, dynamic> && !yaEnLotes.containsKey(e.key)) {
            final parsed = ObservacionSupervisor.deJson(e.value as Map<String, dynamic>);
            if (parsed.activa) mapaObs[e.key] = parsed;
          }
        }
      } catch (_) {}
    } else if (archivoV1.existsSync()) {
      try {
        final crudo = jsonDecode(archivoV1.readAsStringSync()) as Map<String, dynamic>;
        for (final e in crudo.entries) {
          final msVal = (e.value as num?)?.toInt();
          if (msVal != null && !yaEnLotes.containsKey(e.key)) {
            mapaEsc[e.key] = DateTime.fromMillisecondsSinceEpoch(msVal);
          }
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
      _escaneados = mapaEsc;
      _observaciones = mapaObs;
      _yaEnLotes = yaEnLotes;
      _lotesGuardados = lotesGuardados;
      _filtroFechas = null;
      _ultimaCompraEscaneada = null;
      _cargando = false;
    });
  }

  Future<void> _guardarBorrador() async {
    final scope = AppScope.of(context);
    final f = _archivoEstadoBorrador(_activa, scope.fotos.carpetaBase);
    await f.parent.create(recursive: true);
    final data = {
      'escaneados': {for (final e in _escaneados.entries) e.key: e.value.millisecondsSinceEpoch},
      'observaciones': {
        for (final e in _observaciones.entries)
          if (e.value.activa) e.key: e.value.aJson(),
      },
    };
    await f.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> _procesarLectura(String bruto) async {
    final codigo = leerCodigoEscaneado(bruto);
    final d = AppScope.of(context).dispositivo;
    final vibrar = d?.vibrar ?? true;

    if (codigo == null) {
      if (vibrar) HapticFeedback.heavyImpact();
      setState(() {
        _ultimoAviso = tr('Ese código no tiene formato de sticker CataLog', 'That code is not a CataLog sticker format');
        _ultimoOk = false;
        _ultimaCompraEscaneada = null;
      });
      return;
    }

    // 1. Bloqueo anti-repetición contra Lotes de Supervisor ya guardados.
    final previo = _yaEnLotes[codigo] ?? await AppScope.of(context).supervisor.buscarYaRevisado(codigo);
    if (!mounted) return;
    if (previo != null) {
      if (vibrar) HapticFeedback.heavyImpact();
      setState(() {
        _yaEnLotes[codigo] = previo;
        _ultimoAviso = tr(
          'No se repite: $codigo ya fue contado en «${previo.loteNombre}» (${fechaCorta(previo.cerradoEn)})',
          'Not repeated: $codigo was already counted in "${previo.loteNombre}" (${fechaCorta(previo.cerradoEn)})',
        );
        _ultimoOk = false;
        _ultimaCompraEscaneada = null;
      });
      return;
    }

    final compra = _catalogo.where((c) => c.codigo == codigo).firstOrNull;
    final yaEstaba = _escaneados.containsKey(codigo);

    if (compra != null && compra.anulada) {
      if (vibrar) HapticFeedback.heavyImpact();
      setState(() {
        _ultimoAviso = tr('$codigo figura como COMPRA ANULADA', '$codigo is marked as VOIDED PURCHASE');
        _ultimoOk = false;
        _ultimaCompraEscaneada = compra;
      });
      return;
    }

    final ahora = DateTime.now();
    _escaneados[codigo] = _escaneados[codigo] ?? ahora;
    await _guardarBorrador();
    if (!mounted) return;

    if (compra == null) {
      if (vibrar) HapticFeedback.mediumImpact();
      setState(() {
        _ultimoAviso = tr(
          'Código $codigo escaneado (sin ficha previa cargada en este envío)',
          'Code $codigo scanned (no prior record in this package)',
        );
        _ultimoOk = true;
        _ultimaCompraEscaneada = null;
      });
      return;
    }

    if (vibrar) HapticFeedback.mediumImpact();
    if (d?.sonar ?? true) SystemSound.play(SystemSoundType.click);
    if (!yaEstaba) {
      Notificaciones.avisarCataliticoEscaneado(
        d,
        codigo: codigo,
        detalle: '${tr('Verificado', 'Verified')} · ${compra.tipoConLlenado} · ${clp(compra.precio)}',
      );
    }

    setState(() {
      _ultimoAviso = yaEstaba
          ? tr('$codigo ya estaba verificado en esta sesión (${clp(compra.precio)})',
              '$codigo is already verified in this session (${clp(compra.precio)})')
          : tr('Verificado $codigo · ${compra.tipoConLlenado} · ${clp(compra.precio)}',
              'Verified $codigo · ${compra.tipoConLlenado} · ${clp(compra.precio)}');
      _ultimoOk = true;
      _ultimaCompraEscaneada = compra;
    });
  }

  Future<void> _editarObservacion(String codigo, Compra? compra) async {
    final actual = _observaciones[codigo] ?? ObservacionSupervisor.vacia;
    var tipoSel = actual.tipo == TipoObservacionSupervisor.ninguna
        ? TipoObservacionSupervisor.ceramicaPartida
        : actual.tipo;
    final notaCtrl = TextEditingController(text: actual.nota);

    final res = await showModalBottomSheet<ObservacionSupervisor?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, color: CatalogColors.rojo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('Observación / Discrepancia', 'Observation / Discrepancy'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$codigo${compra != null ? ' · ${compra.tipoConLlenado} · ${clp(compra.precio)}' : ''}\n'
                    '${tr('Saldrá destacado en rojo en la revisión y en el Excel.', 'Will be highlighted in red in the review and in Excel.')}',
                    style: etiqueta.copyWith(height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final op in TipoObservacionSupervisor.values.where(
                        (t) => t != TipoObservacionSupervisor.ninguna,
                      ))
                        ChoiceChip(
                          label: Text(op.etiqueta),
                          selected: tipoSel == op,
                          selectedColor: CatalogColors.rojo.withValues(alpha: 0.16),
                          side: BorderSide(
                            color: tipoSel == op ? CatalogColors.rojo : CatalogColors.borde,
                            width: tipoSel == op ? 1.6 : 1,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: tipoSel == op ? FontWeight.w700 : FontWeight.w500,
                            color: tipoSel == op ? CatalogColors.rojo : CatalogColors.texto,
                          ),
                          onSelected: (_) => setLocal(() => tipoSel = op),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notaCtrl,
                    maxLines: 2,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: tr('Detalle opcional (ej. vino partido a la mitad)', 'Optional note (e.g. broken in half)'),
                      prefixIcon: const Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (actual.activa) ...[
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: CatalogColors.acero),
                          onPressed: () => Navigator.pop(ctx, ObservacionSupervisor.vacia),
                          icon: const Icon(Icons.clear, size: 18),
                          label: Text(tr('Quitar', 'Clear')),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: CatalogColors.rojo,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(
                            ctx,
                            ObservacionSupervisor(tipo: tipoSel, nota: notaCtrl.text),
                          ),
                          icon: const Icon(Icons.flag_rounded),
                          label: Text(tr('Guardar observación', 'Save discrepancy')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    notaCtrl.dispose();
    if (res == null || !mounted) return;
    setState(() {
      if (res.activa) {
        _observaciones[codigo] = res;
        // Si el supervisor inspeccionó la pieza y le puso observación, también queda verificada físicamente.
        _escaneados[codigo] ??= DateTime.now();
      } else {
        _observaciones.remove(codigo);
      }
    });
    await _guardarBorrador();
  }

  bool _entraEnFiltroFecha(DateTime? f) {
    final rango = _filtroFechas;
    if (rango == null) return true;
    if (f == null) return true;
    final inicio = DateTime(rango.start.year, rango.start.month, rango.start.day);
    final finExcl = DateTime(rango.end.year, rango.end.month, rango.end.day).add(const Duration(days: 1));
    return !f.isBefore(inicio) && f.isBefore(finExcl);
  }

  /// Construye las filas activas de la revisión actual (excluyendo las ya cerradas
  /// en lotes de supervisor anteriores a menos que `_mostrarYaRevisados` esté activo).
  List<FilaRevisionExcel> _armarFilas({bool aplicarFiltroFecha = true}) {
    final porCodigo = {for (final c in _catalogo) c.codigo: c};
    final resultado = <FilaRevisionExcel>[];

    final codigosEscaneados = _escaneados.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in codigosEscaneados) {
      if (!_mostrarYaRevisados && _yaEnLotes.containsKey(e.key)) continue;
      final c = porCodigo[e.key];
      if (aplicarFiltroFecha && !_entraEnFiltroFecha(c?.fechaCompra ?? e.value)) continue;
      resultado.add(FilaRevisionExcel(
        codigo: e.key,
        compra: c,
        escaneadoEn: e.value,
        observacion: _observaciones[e.key] ?? ObservacionSupervisor.vacia,
      ));
    }

    for (final c in _catalogo) {
      if (_escaneados.containsKey(c.codigo)) continue;
      if (!_mostrarYaRevisados && _yaEnLotes.containsKey(c.codigo)) continue;
      if (aplicarFiltroFecha && !_entraEnFiltroFecha(c.fechaCompra)) continue;
      resultado.add(FilaRevisionExcel(
        codigo: c.codigo,
        compra: c,
        observacion: _observaciones[c.codigo] ?? ObservacionSupervisor.vacia,
      ));
    }
    return resultado;
  }

  Future<(String comprador, String prefijo, String rango)> _datosEncabezado() async {
    final comprasLocal = AppScope.of(context).compras;
    final comprador = _activa?.origen.isNotEmpty == true
        ? _activa!.origen
        : (await comprasLocal.leerAjuste('nombre') ?? '');
    final prefijo = _activa?.prefijo.isNotEmpty == true
        ? _activa!.prefijo
        : await comprasLocal.prefijo();
    String rango = _activa?.rango ?? '';
    if (_filtroFechas != null) {
      final d = _filtroFechas!.start;
      final h = _filtroFechas!.end;
      rango = d == h ? fechaCorta(d) : '${fechaCorta(d)} – ${fechaCorta(h)}';
    }
    return (comprador, prefijo, rango);
  }

  Future<void> _guardarLoteSupervisor() async {
    final filas = _armarFilas();
    final verificadas = filas.where((f) => f.verificado && !_yaEnLotes.containsKey(f.codigo)).toList();
    if (verificadas.isEmpty) {
      avisar(
        context,
        tr(
          'Escanea primero los catalíticos con la cámara para guardarlos como Lote de Supervisor',
          'Scan converters with the camera first to save them as a Supervisor Batch',
        ),
      );
      return;
    }

    final (comprador, prefijo, rango) = await _datosEncabezado();
    if (!mounted) return;
    final sugerido = [
      tr('Lote Sup.', 'Sup. Batch'),
      if (comprador.isNotEmpty) comprador else if (prefijo.isNotEmpty) prefijo,
      fechaCorta(DateTime.now()),
    ].join(' · ');

    final nomCtrl = TextEditingController(text: sugerido);
    final notasCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Guardar Lote de Supervisor', 'Save Supervisor Batch')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Se guardarán ${verificadas.length} catalíticos verificados en este lote de supervisor. Una vez guardados, ninguno de esos códigos podrá volver a repetirse en otro lote futuro.',
                  'Saves ${verificadas.length} verified converters in this supervisor batch. Once saved, none of these codes can be repeated in future batches.',
                ),
                style: TextStyle(fontSize: 13.5, color: CatalogColors.acero, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nomCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: tr('Nombre del lote', 'Batch name'),
                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notasCtrl,
                decoration: InputDecoration(
                  labelText: tr('Notas (opcional)', 'Notes (optional)'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(tr('Guardar lote', 'Save batch')),
          ),
        ],
      ),
    );

    final nombreElegido = nomCtrl.text;
    final notasElegidas = notasCtrl.text;
    nomCtrl.dispose();
    notasCtrl.dispose();
    if (confirmar != true || !mounted) return;

    try {
      final lote = await AppScope.of(context).supervisor.guardarLote(
            nombre: nombreElegido,
            comprador: comprador,
            prefijo: prefijo,
            rangoTexto: rango,
            notas: notasElegidas,
            items: [
              for (final f in verificadas)
                BorradorItemSupervisor(
                  codigo: f.codigo,
                  compra: f.compra,
                  escaneadoEn: f.escaneadoEn,
                  observacion: f.observacion,
                ),
            ],
          );
      for (final f in verificadas) {
        _escaneados.remove(f.codigo);
        _observaciones.remove(f.codigo);
      }
      await _guardarBorrador();
      await _refrescarLotesSupervisor();
      if (!mounted) return;
      setState(() {
        _ultimoAviso = tr(
          'Lote «${lote.nombre}» guardado (${lote.cantidad} piezas bloqueadas contra repetición)',
          'Batch "${lote.nombre}" saved (${lote.cantidad} units locked against duplicates)',
        );
        _ultimoOk = true;
        _ultimaCompraEscaneada = null;
      });
      await _mostrarAccionesPostCierreLote(lote, verificadas);
    } on DatosInvalidos catch (e) {
      if (mounted) avisar(context, e.mensaje);
    } catch (e) {
      if (mounted) avisar(context, '${tr('No se pudo guardar el lote', 'Could not save batch')}: $e');
    }
  }

  Future<void> _mostrarAccionesPostCierreLote(
    LoteSupervisor lote,
    List<FilaRevisionExcel> filasGuardadas,
  ) async {
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.verified_rounded, color: CatalogColors.verde, size: 40),
        title: Text(tr('Lote de Supervisor cerrado', 'Supervisor Batch saved')),
        content: Text(
          tr(
            '«${lote.nombre}» quedó guardado con ${lote.cantidad} catalíticos (${clp(lote.totalVerificado)}).\n\n¿Quieres imprimir la Etiqueta QR para el saco/caja o exportar el Excel?',
            '"${lote.nombre}" saved with ${lote.cantidad} converters (${clp(lote.totalVerificado)}).\n\nPrint the Master QR Bag Label or export Excel now?',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Listo', 'Done'))),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'excel'),
            icon: const Icon(Icons.table_view_outlined, size: 18),
            label: const Text('Excel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'etiqueta'),
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: Text(tr('Etiqueta Saco', 'Bag Label')),
          ),
        ],
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'etiqueta') {
      await _mostrarEtiquetaDeLoteSupervisor(lote);
    } else if (accion == 'excel') {
      await _exportarExcelDeLoteSupervisor(lote);
    }
  }

  Future<void> _mostrarEtiquetaDeLoteSupervisor(LoteSupervisor lote) async {
    final items = await AppScope.of(context).supervisor.itemsDeLote(lote.id);
    if (!mounted) return;
    var cer = 0, met = 0, dpf = 0;
    for (final it in items) {
      final t = it.tipo.toLowerCase();
      if (t.contains('dpf')) {
        dpf++;
      } else if (t.contains('met')) {
        met++;
      } else {
        cer++;
      }
    }
    final datos = DatosEtiquetaLote(
      codigoLote: lote.codigoLote,
      nombreLote: lote.nombre,
      fecha: lote.cerradoEn,
      totalPiezas: items.length,
      ceramicos: cer,
      metalicos: met,
      dpf: dpf,
      conObservacion: lote.conObservacion,
      responsable: [if (lote.comprador.isNotEmpty) lote.comprador, if (lote.prefijo.isNotEmpty) lote.prefijo].join(' · '),
      esSupervisor: true,
    );
    await mostrarDialogoEtiquetaLote(context, datos);
  }

  Future<void> _exportarExcelDeLoteSupervisor(LoteSupervisor lote) async {
    final items = await AppScope.of(context).supervisor.itemsDeLote(lote.id);
    if (!mounted) return;
    final filas = items.map(FilaRevisionExcel.deItemLoteSupervisor).toList();
    final bytes = excelDeRevisionSupervisor(
      filas,
      titulo: lote.nombre,
      comprador: lote.comprador,
      prefijo: lote.prefijo,
      rangoFechas: lote.rangoTexto,
    );
    await compartirExcel(
      bytes,
      '${lote.codigoLote}-${lote.nombre}.xlsx',
      texto: '${lote.nombre} · ${contarCataliticos(lote.cantidad)} · ${clp(lote.totalVerificado)}',
    );
  }

  Future<void> _exportarExcel() async {
    final filas = _armarFilas();
    if (filas.isEmpty) {
      avisar(
        context,
        tr(
          'Escanea al menos un catalítico o recibe compras para generar el Excel',
          'Scan at least one converter or receive purchases to generate the Excel',
        ),
      );
      return;
    }
    setState(() => _exportando = true);
    try {
      final (comprador, prefijo, rango) = await _datosEncabezado();
      final bytes = excelDeRevisionSupervisor(
        filas,
        comprador: comprador,
        prefijo: prefijo,
        rangoFechas: rango,
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
      final rangoTxt = contenido.rango.isNotEmpty ? ' (${contenido.rango})' : '';
      avisar(
        context,
        tr(
          'Cargadas ${contenido.compras} compras$rangoTxt listas para revisar',
          'Loaded ${contenido.compras} purchases$rangoTxt ready to review',
        ),
      );
    }
  }

  Future<void> _abrirFichaSoloLectura(Compra c) async {
    final scopePadre = AppScope.of(context);
    final base = _baseExterna ?? scopePadre.base;
    final carpeta = _carpetaFotosActiva;
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
    if (_escaneados.isEmpty && _observaciones.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Reiniciar revisión en curso?', 'Reset current review?')),
        content: Text(
          tr(
            'Se desmarcan los catalíticos escaneados de esta pantalla. Los Lotes de Supervisor ya guardados siguen protegidos.',
            'Clears checkmarks on this screen. Saved Supervisor Batches remain locked and protected.',
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
      _observaciones.clear();
      _ultimoAviso = null;
      _ultimaCompraEscaneada = null;
    });
    await _guardarBorrador();
  }

  Future<void> _elegirRangoFechas() async {
    final ahora = DateTime.now();
    final elegido = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2018),
      lastDate: ahora,
      initialDateRange: _filtroFechas,
      helpText: tr('Filtrar compras por fecha', 'Filter purchases by date'),
    );
    if (!mounted || elegido == null) return;
    setState(() => _filtroFechas = elegido);
  }

  Future<void> _verDetalleLoteGuardado(LoteSupervisor lote) async {
    final items = await AppScope.of(context).supervisor.itemsDeLote(lote.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lote.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      '${lote.codigoLote} · ${fechaHora(lote.cerradoEn)} · ${contarCataliticos(lote.cantidad)} · ${clp(lote.totalVerificado)}',
                      style: etiqueta,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final it = items[i];
                    final obs = it.observacion.activa;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: obs ? CatalogColors.rojo : CatalogColors.verde.withValues(alpha: 0.65),
                            width: 1.4,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(it.codigo, style: mono(size: 13.5, weight: FontWeight.w700))),
                                  Text(clp(it.precio), style: mono(size: 14.5)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  if (it.fechaCompra != null) fechaCorta(it.fechaCompra!),
                                  if (it.vendedor.isNotEmpty) it.vendedor,
                                  if (it.tipo.isNotEmpty) it.tipo,
                                  it.llenado.etiqueta,
                                ].join(' · '),
                                style: etiqueta,
                              ),
                              if (obs) ...[
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: CatalogColors.rojo.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Text(
                                    it.observacion.resumen,
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: CatalogColors.rojo),
                                  ),
                                ),
                              ],
                            ],
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
      ),
    );
  }

  Future<void> _eliminarLoteSupervisor(LoteSupervisor lote) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Borrar este Lote de Supervisor?', 'Delete this Supervisor Batch?')),
        content: Text(
          tr(
            'Los ${lote.cantidad} códigos de «${lote.nombre}» dejarán de estar bloqueados y podrán volver a contarse en otra revisión.',
            'The ${lote.cantidad} codes in "${lote.nombre}" will be unlocked and allowed in future reviews again.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar', 'Cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Borrar lote', 'Delete batch'), style: TextStyle(color: CatalogColors.rojo)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (!await confirmarConHuella(context, tr('Confirma para borrar ${lote.nombre}', 'Confirm to delete ${lote.nombre}'))) {
      return;
    }
    if (!mounted) return;
    await AppScope.of(context).supervisor.eliminarLote(lote.id);
    await _refrescarLotesSupervisor();
  }

  Future<void> _mostrarGuia() => mostrarGuia(context, [
        PasoGuia(
          clave: _gWifi,
          icono: Icons.wifi,
          titulo: tr('Recibir por fechas (WhatsApp o Wi-Fi)', 'Receive by date (WhatsApp or Wi-Fi)'),
          texto: tr(
            'Recibe solo las compras del día o semana que eligió el comprador, sin arrastrar todo el historial.',
            'Receive only the day or week chosen by the buyer without loading the entire history.',
          ),
        ),
        if (_mostrarCamara && _vista == _VistaSupervisor.activa)
          PasoGuia(
            clave: _gCamara,
            icono: Icons.qr_code_scanner,
            titulo: tr('Escáner anti-repetición', 'Anti-duplicate scanner'),
            texto: tr(
              'Verifica cada sticker con la cámara, comprueba su foto y cerámica, y bloquea piezas que ya hayan sido contadas en otro Lote de Supervisor.',
              'Verifies each sticker with the camera, shows its photo & honeycomb state, and blocks items already counted in a previous Supervisor Batch.',
            ),
          ),
        if (_vista == _VistaSupervisor.activa)
          PasoGuia(
            clave: _gResumen,
            icono: Icons.fact_check_outlined,
            titulo: tr('Lote de Supervisor, Etiqueta QR y Excel', 'Supervisor Batch, QR Label & Excel'),
            texto: tr(
              'Marca observaciones en 1 toque, guarda la revisión como Lote de Supervisor para no repetir piezas, imprime la etiqueta del saco o exporta el Excel con logo y Tablas Dinámicas.',
              'Flag discrepancies in 1 tap, save as a Supervisor Batch to prevent duplicates, print the Master Bag QR label, or export Excel with logo and PivotTables.',
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final sinFiltroFecha = _armarFilas(aplicarFiltroFecha: false);
    final todasFilas = _armarFilas(aplicarFiltroFecha: true);

    final verificadasCount = todasFilas.where((f) => f.verificado && !f.anulada).length;
    final pendientesCount = todasFilas.where((f) => !f.verificado && !f.anulada).length;
    final observadasCount = todasFilas.where((f) => f.observacion.activa).length;
    final omitidasPrevias = _catalogo.where((c) => _yaEnLotes.containsKey(c.codigo)).length;

    final montoVerificado = todasFilas
        .where((f) => f.verificado && !f.anulada)
        .fold<int>(0, (s, f) => s + f.precioEfectivo);
    final montoPendiente = todasFilas
        .where((f) => !f.verificado && !f.anulada)
        .fold<int>(0, (s, f) => s + f.precioEfectivo);
    final totalObjetivo = verificadasCount + pendientesCount;
    final progreso = totalObjetivo == 0 ? 0.0 : (verificadasCount / totalObjetivo).clamp(0.0, 1.0);

    final visibles = switch (_filtro) {
      _FiltroRevision.todos => todasFilas,
      _FiltroRevision.pendientes => todasFilas.where((f) => !f.verificado && !f.anulada).toList(),
      _FiltroRevision.verificados => todasFilas.where((f) => f.verificado).toList(),
      _FiltroRevision.observados => todasFilas.where((f) => f.observacion.activa).toList(),
    };

    final origenTexto = _activa != null
        ? '${_activa!.nombre}${_activa!.prefijo.isNotEmpty ? ' (${_activa!.prefijo})' : ''}'
            '${_activa!.rango.isNotEmpty ? ' · ${_activa!.rango}' : ''}'
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
          if (_vista == _VistaSupervisor.activa)
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
                case 'toggle_previos':
                  setState(() => _mostrarYaRevisados = !_mostrarYaRevisados);
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
                value: 'zip',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(tr('Cargar archivo .zip (WhatsApp)', 'Load .zip file (WhatsApp)')),
                ),
              ),
              PopupMenuItem(
                value: 'wifi_enviar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(tr('Enviar por Wi-Fi', 'Send over Wi-Fi')),
                ),
              ),
              if (omitidasPrevias > 0)
                PopupMenuItem(
                  value: 'toggle_previos',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_mostrarYaRevisados ? Icons.visibility_off : Icons.visibility),
                    title: Text(
                      _mostrarYaRevisados
                          ? tr('Ocultar ya contados en otros lotes ($omitidasPrevias)', 'Hide items in prior batches ($omitidasPrevias)')
                          : tr('Ver ya contados en otros lotes ($omitidasPrevias)', 'Show items in prior batches ($omitidasPrevias)'),
                    ),
                  ),
                ),
              PopupMenuItem(
                value: 'reiniciar',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restart_alt),
                  title: Text(tr('Reiniciar conteo actual', 'Reset current count')),
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
                      Expanded(
                        child: Text(
                          '${r.nombre}${r.rango.isNotEmpty ? ' · ${r.rango}' : ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: SegmentedButton<_VistaSupervisor>(
                      segments: [
                        ButtonSegment(
                          value: _VistaSupervisor.activa,
                          icon: const Icon(Icons.qr_code_scanner, size: 18),
                          label: Text(tr('Revisión activa', 'Active review')),
                        ),
                        ButtonSegment(
                          value: _VistaSupervisor.lotes,
                          icon: const Icon(Icons.inventory_2_outlined, size: 18),
                          label: Text(
                            '${tr('Lotes Supervisor', 'Supervisor Batches')} (${_lotesGuardados.length})',
                          ),
                        ),
                      ],
                      selected: {_vista},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _vista = s.first),
                    ),
                  ),
                  if (_vista == _VistaSupervisor.lotes)
                    Expanded(child: _construirVistaLotes())
                  else
                    Expanded(
                      child: _construirVistaActiva(
                        origenTexto: origenTexto,
                        sinFiltroFecha: sinFiltroFecha,
                        todasFilas: todasFilas,
                        visibles: visibles,
                        verificadasCount: verificadasCount,
                        pendientesCount: pendientesCount,
                        observadasCount: observadasCount,
                        omitidasPrevias: omitidasPrevias,
                        montoVerificado: montoVerificado,
                        montoPendiente: montoPendiente,
                        progreso: progreso,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _construirVistaActiva({
    required String origenTexto,
    required List<FilaRevisionExcel> sinFiltroFecha,
    required List<FilaRevisionExcel> todasFilas,
    required List<FilaRevisionExcel> visibles,
    required int verificadasCount,
    required int pendientesCount,
    required int observadasCount,
    required int omitidasPrevias,
    required int montoVerificado,
    required int montoPendiente,
    required double progreso,
  }) {
    // Días únicos disponibles en el catálogo cargado para chips rápidos de fechas.
    final conteoPorDia = <DateTime, int>{};
    for (final f in sinFiltroFecha) {
      final fc = f.fechaEfectiva;
      if (fc != null) {
        final dia = DateTime(fc.year, fc.month, fc.day);
        conteoPorDia[dia] = (conteoPorDia[dia] ?? 0) + 1;
      }
    }
    final diasDisponibles = conteoPorDia.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mostrarCamara)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: SizedBox(
              key: _gCamara,
              height: 162,
              child: Stack(
                children: [
                  Positioned.fill(child: EscanerVista(alLeer: _procesarLectura)),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      ),
                      onPressed: () async {
                        final t = await pedirCodigoManual(context);
                        if (t != null && t.trim().isNotEmpty) await _procesarLectura(t);
                      },
                      icon: const Icon(Icons.keyboard_outlined, size: 16),
                      label: Text(tr('Código a mano', 'Manual code'), style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_ultimoAviso != null) _bannerUltimoEscaneo(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: _tarjetaResumenEjecutivo(
            origenTexto: origenTexto,
            verificadasCount: verificadasCount,
            pendientesCount: pendientesCount,
            observadasCount: observadasCount,
            omitidasPrevias: omitidasPrevias,
            montoVerificado: montoVerificado,
            montoPendiente: montoPendiente,
            progreso: progreso,
          ),
        ),
        // Filtros por estado + fechas
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              _chipEstado(_FiltroRevision.todos, '${tr('Todos', 'All')} (${todasFilas.length})'),
              const SizedBox(width: 6),
              _chipEstado(_FiltroRevision.pendientes, '${tr('Faltan', 'Pending')} ($pendientesCount)'),
              const SizedBox(width: 6),
              _chipEstado(_FiltroRevision.verificados, '${tr('Verificados', 'Verified')} ($verificadasCount)'),
              if (observadasCount > 0) ...[
                const SizedBox(width: 6),
                _chipEstado(
                  _FiltroRevision.observados,
                  '${tr('Con obs.', 'Flagged')} ($observadasCount)',
                  esRojo: true,
                ),
              ],
            ],
          ),
        ),
        if (diasDisponibles.length > 1 || _filtroFechas != null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.calendar_today, size: 14),
                  label: Text(tr('Todas las fechas', 'All dates'), style: const TextStyle(fontSize: 12)),
                  selected: _filtroFechas == null,
                  onSelected: (_) => setState(() => _filtroFechas = null),
                ),
                const SizedBox(width: 6),
                for (final dia in diasDisponibles.take(7)) ...[
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${dia.day.toString().padLeft(2, '0')}/${dia.month.toString().padLeft(2, '0')} (${conteoPorDia[dia]})',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _filtroFechas != null &&
                        _filtroFechas!.start == dia &&
                        _filtroFechas!.end == dia,
                    onSelected: (_) => setState(() => _filtroFechas = DateTimeRange(start: dia, end: dia)),
                  ),
                  const SizedBox(width: 6),
                ],
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.date_range, size: 15),
                  label: Text(tr('Rango…', 'Range…'), style: const TextStyle(fontSize: 12)),
                  onPressed: _elegirRangoFechas,
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
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              omitidasPrevias > 0 && todasFilas.isEmpty
                                  ? Icons.verified_rounded
                                  : Icons.qr_code_scanner,
                              size: 40,
                              color: omitidasPrevias > 0 && todasFilas.isEmpty
                                  ? CatalogColors.verde
                                  : CatalogColors.naranja,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              omitidasPrevias > 0 && todasFilas.isEmpty
                                  ? tr(
                                      'Todos los catalíticos cargados ($omitidasPrevias) ya fueron revisados y cerrados en Lotes de Supervisor anteriores.',
                                      'All loaded converters ($omitidasPrevias) were already reviewed and saved in prior Supervisor Batches.',
                                    )
                                  : (todasFilas.isEmpty
                                      ? tr(
                                          'Recibe las compras por fecha (WhatsApp o Wi-Fi) o apunta la cámara a los stickers físicos.',
                                          'Receive purchases by date (WhatsApp or Wi-Fi) or point the camera at physical stickers.',
                                        )
                                      : tr('No hay catalíticos en este filtro.', 'No converters match this filter.')),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14.5, height: 1.4, color: CatalogColors.acero),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : _construirListaAgrupadaPorFecha(visibles),
        ),
      ],
    );
  }

  Widget _chipEstado(_FiltroRevision valor, String texto, {bool esRojo = false}) {
    final sel = _filtro == valor;
    final col = esRojo ? CatalogColors.rojo : CatalogColors.naranja;
    return ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(texto),
      selected: sel,
      selectedColor: col.withValues(alpha: 0.2),
      side: BorderSide(color: sel ? col : CatalogColors.borde, width: sel ? 1.5 : 1),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
        color: sel && esRojo ? CatalogColors.rojo : CatalogColors.texto,
      ),
      onSelected: (_) => setState(() => _filtro = valor),
    );
  }

  Widget _bannerUltimoEscaneo() {
    final c = _ultimaCompraEscaneada;
    final color = _ultimoOk ? CatalogColors.verde : CatalogColors.rojo;
    File? fotoArchivo;
    if (c?.fotoPath != null) {
      final f = FotosStore(_carpetaFotosActiva).archivo(c!.fotoPath!);
      if (f.existsSync()) fotoArchivo = f;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.4),
        ),
        child: Row(
          children: [
            if (fotoArchivo != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(fotoArchivo, width: 42, height: 42, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
            ] else ...[
              Icon(_ultimoOk ? Icons.check_circle : Icons.error, color: color, size: 22),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ultimoAviso!,
                    style: TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700, color: color),
                  ),
                  if (c != null)
                    Text(
                      [
                        c.vendedor,
                        if (c.codigoFabrica.isNotEmpty) c.codigoFabrica,
                        if (c.autos.isNotEmpty) c.autos,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: etiqueta.copyWith(fontSize: 11.5),
                    ),
                ],
              ),
            ),
            if (c != null && _ultimoOk)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Marcar observación', 'Flag discrepancy'),
                icon: Icon(Icons.flag_outlined, color: CatalogColors.rojo, size: 20),
                onPressed: () => _editarObservacion(c.codigo, c),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaResumenEjecutivo({
    required String origenTexto,
    required int verificadasCount,
    required int pendientesCount,
    required int observadasCount,
    required int omitidasPrevias,
    required int montoVerificado,
    required int montoPendiente,
    required double progreso,
  }) {
    final pctTexto = '${(progreso * 100).round()}%';
    return Container(
      key: _gResumen,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF14385C), CatalogColors.marino],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: CatalogColors.marino.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Anillo de progreso animado
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: CircularProgressIndicator(
                        value: progreso,
                        strokeWidth: 5.5,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          progreso >= 1.0 && verificadasCount > 0
                              ? const Color(0xFF42E39B)
                              : CatalogColors.naranja,
                        ),
                      ),
                    ),
                    Text(
                      pctTexto,
                      style: mono(size: 13, weight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      origenTexto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              clp(montoVerificado),
                              style: mono(size: 23, weight: FontWeight.w700, color: CatalogColors.naranja),
                            ),
                          ),
                        ),
                        if (montoPendiente > 0) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${tr('falta', 'left')} ${clp(montoPendiente)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mono(size: 11.5, color: const Color(0xB3FFFFFF)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _pastillaKpi('${tr('OK', 'OK')}: $verificadasCount', const Color(0xFF42E39B)),
                        _pastillaKpi('${tr('Faltan', 'Pending')}: $pendientesCount', const Color(0xFFFFB74D)),
                        if (observadasCount > 0)
                          _pastillaKpi('${tr('Obs.', 'Flagged')}: $observadasCount', const Color(0xFFFF8A80)),
                        if (omitidasPrevias > 0 && !_mostrarYaRevisados)
                          _pastillaKpi(
                            '${tr('En lote previo', 'Prior batch')}: $omitidasPrevias',
                            const Color(0xFF90CAF9),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: verificadasCount > 0
                        ? const Color(0xFF1D9E75)
                        : Colors.white.withValues(alpha: 0.14),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: _guardarLoteSupervisor,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr('Guardar Lote Supervisor', 'Save Supervisor Batch'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: _gExcel,
                style: FilledButton.styleFrom(
                  backgroundColor: CatalogColors.naranja,
                  foregroundColor: CatalogColors.marino,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: _exportando ? null : _exportarExcel,
                icon: _exportando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.table_view_outlined, size: 18),
                label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pastillaKpi(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          texto,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );

  /// Agrupa los catalíticos por fecha de compra (el día más nuevo arriba) para una lectura clara.
  Widget _construirListaAgrupadaPorFecha(List<FilaRevisionExcel> items) {
    final grupos = <DateTime?, List<FilaRevisionExcel>>{};
    for (final it in items) {
      final f = it.fechaEfectiva;
      final clave = f == null ? null : DateTime(f.year, f.month, f.day);
      (grupos[clave] ??= []).add(it);
    }
    final claves = grupos.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return -1;
        if (b == null) return 1;
        return b.compareTo(a);
      });

    final entradas = <Widget>[];
    for (final dia in claves) {
      final listaDia = grupos[dia]!;
      final verifDia = listaDia.where((x) => x.verificado && !x.anulada).length;
      final montoDia = listaDia.fold<int>(0, (s, x) => s + x.precioEfectivo);
      final tituloDia = dia == null
          ? tr('Escaneados sin ficha previa', 'Scanned without prior record')
          : capitalizar(fechaLarga(dia));
      entradas.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Row(
            children: [
              const Icon(Icons.event_note, size: 16, color: CatalogColors.naranja),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tituloDia,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$verifDia/${listaDia.length} · ${clp(montoDia)}',
                style: mono(size: 12, color: CatalogColors.acero, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
      for (final item in listaDia) {
        entradas.add(_tarjetaItemRevision(item));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: entradas,
    );
  }

  Widget _tarjetaItemRevision(FilaRevisionExcel item) {
    final c = item.compra;
    final verif = item.verificado;
    final obs = item.observacion;
    final yaPrevio = _yaEnLotes[item.codigo];
    final esRoja = obs.activa || item.anulada;

    final colorBorde = yaPrevio != null
        ? CatalogColors.acero.withValues(alpha: 0.45)
        : (esRoja
            ? CatalogColors.rojo
            : (verif ? CatalogColors.verde.withValues(alpha: 0.78) : CatalogColors.naranja.withValues(alpha: 0.78)));

    File? miniatura;
    if (c?.fotoPath != null) {
      final arch = FotosStore(_carpetaFotosActiva).archivo(c!.fotoPath!);
      if (arch.existsSync()) miniatura = arch;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: esRoja ? CatalogColors.rojo.withValues(alpha: 0.05) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: colorBorde, width: esRoja ? 1.9 : 1.5),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: c != null ? () => _abrirFichaSoloLectura(c) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (miniatura != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(miniatura, width: 46, height: 46, fit: BoxFit.cover),
                  )
                else if (c != null)
                  MarcaTipo(material: c.material, anulada: c.anulada, tamano: 42)
                else
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: CatalogColors.verde,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code, color: Colors.white, size: 22),
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
                              style: mono(size: 13, weight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (c != null)
                            Text(
                              clp(c.precio),
                              style: mono(size: 14.5, weight: FontWeight.w700),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c != null
                            ? [
                                c.vendedor,
                                if (c.codigoFabrica.isNotEmpty) c.codigoFabrica,
                                if (c.autos.isNotEmpty) c.autos,
                              ].join(' · ')
                            : tr('Código escaneado directo', 'Directly scanned code'),
                        style: etiqueta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (c != null) _pastillaLlenado(c.llenado),
                          if (yaPrevio != null)
                            _pastillaEstado(
                              Icons.lock_outline,
                              '${tr('Ya en', 'In')} ${yaPrevio.loteNombre}',
                              CatalogColors.acero,
                            )
                          else if (obs.activa)
                            _pastillaEstado(Icons.flag_rounded, obs.resumen, CatalogColors.rojo)
                          else if (verif)
                            _pastillaEstado(
                              Icons.check_circle,
                              '${tr('Verificado', 'Verified')} · ${hora(item.escaneadoEn!)}',
                              CatalogColors.verde,
                            )
                          else
                            _pastillaEstado(
                              Icons.schedule,
                              tr('Falta escanear', 'Pending scan'),
                              CatalogColors.naranja,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (yaPrevio == null)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('Observación / Discrepancia', 'Flag discrepancy'),
                    icon: Icon(
                      obs.activa ? Icons.flag_rounded : Icons.flag_outlined,
                      size: 20,
                      color: obs.activa ? CatalogColors.rojo : CatalogColors.acero,
                    ),
                    onPressed: () => _editarObservacion(item.codigo, c),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pastillaLlenado(NivelLlenado niv) {
    final col = switch (niv) {
      NivelLlenado.entero => CatalogColors.verde,
      NivelLlenado.fundido => CatalogColors.rojo,
      _ => CatalogColors.naranja,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        niv.etiqueta,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: col),
      ),
    );
  }

  Widget _pastillaEstado(IconData icono, String texto, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icono, size: 13.5, color: color),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 195),
          child: Text(
            texto,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    );
  }

  Widget _construirVistaLotes() {
    if (_lotesGuardados.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 42, color: CatalogColors.naranja),
                  const SizedBox(height: 10),
                  Text(
                    tr('Todavía no hay Lotes de Supervisor guardados', 'No Supervisor Batches saved yet'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(
                      'Cuando verifiques catalíticos en «Revisión activa» y toques «Guardar Lote Supervisor», quedarán registrados aquí para que ningún código se vuelva a repetir en otro lote.',
                      'When you verify converters in "Active review" and tap "Save Supervisor Batch", they stay logged here so no code can ever be repeated in another batch.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: CatalogColors.acero, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _lotesGuardados.length,
      itemBuilder: (ctx, i) {
        final l = _lotesGuardados[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: l.conObservacion > 0
                    ? CatalogColors.rojo.withValues(alpha: 0.7)
                    : CatalogColors.verde.withValues(alpha: 0.65),
                width: 1.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _verDetalleLoteGuardado(l),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l.nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  l.codigoLote,
                                  fechaHora(l.cerradoEn),
                                  if (l.rangoTexto.isNotEmpty) l.rangoTexto,
                                ].join(' · '),
                                style: etiqueta,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          clp(l.totalVerificado),
                          style: mono(size: 16.5, weight: FontWeight.w700, color: CatalogColors.naranja),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _pastillaEstado(
                          Icons.verified_outlined,
                          '${contarCataliticos(l.cantidad)} (${tr('sin repetir', 'locked')})',
                          CatalogColors.verde,
                        ),
                        if (l.conObservacion > 0)
                          _pastillaEstado(
                            Icons.flag_rounded,
                            '${l.conObservacion} ${tr('con observación', 'with discrepancy')}',
                            CatalogColors.rojo,
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          onPressed: () => _mostrarEtiquetaDeLoteSupervisor(l),
                          icon: const Icon(Icons.qr_code_2, size: 17),
                          label: Text(tr('Etiqueta Saco', 'Bag Label'), style: const TextStyle(fontSize: 12.5)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onPressed: () => _exportarExcelDeLoteSupervisor(l),
                          icon: const Icon(Icons.table_view_outlined, size: 17),
                          label: const Text('Excel', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Borrar lote', 'Delete batch'),
                          icon: Icon(Icons.delete_outline, size: 20, color: CatalogColors.rojo),
                          onPressed: () => _eliminarLoteSupervisor(l),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
