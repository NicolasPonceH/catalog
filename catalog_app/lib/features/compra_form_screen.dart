import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/fotos.dart';
import '../data/ubicacion.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/campo_autocompletar.dart';
import '../widgets/guia.dart';
import 'ficha_screen.dart';

/// Formulario para registrar una compra nueva o corregir una existente.
/// Lo primero es la FECHA Y HORA DE COMPRA: se llena sola y se puede cambiar.
class CompraFormScreen extends StatefulWidget {
  const CompraFormScreen({super.key, this.existente});

  final Compra? existente;

  @override
  State<CompraFormScreen> createState() => _CompraFormScreenState();
}

class _CompraFormScreenState extends State<CompraFormScreen> {
  final _form = GlobalKey<FormState>();
  final _vendedor = TextEditingController();
  final _lugar = TextEditingController();
  final _precio = TextEditingController();
  final _codigoFabrica = TextEditingController();
  final _autos = TextEditingController();
  final _notas = TextEditingController();

  late DateTime _fecha;
  Motor? _motor;
  TipoMaterial? _material;

  double? _lat, _lng, _precision;
  bool _buscandoGps = false;
  String? _errorGps;

  String? _foto;
  String? _fotoOriginal;
  String? _fotoNuevaSinGuardar;

  String? _errorFecha;
  String? _errorTipo;
  bool _guardando = false;
  bool _terminado = false;
  bool _sucio = false;

  List<String> _vendedores = const [];
  List<String> _lugares = const [];
  List<String> _autosUsados = const [];
  List<String> _codigosFabrica = const [];
  ReferenciaPrecio? _referencia;

  // Partes que ilumina la guía.
  final _gFecha = GlobalKey();
  final _gVendedor = GlobalKey();
  final _gLugar = GlobalKey();
  final _gPrecio = GlobalKey();
  final _gTipo = GlobalKey();
  final _gFabrica = GlobalKey();
  final _gFoto = GlobalKey();
  final _gGuardar = GlobalKey();

  bool get _editando => widget.existente != null;

  Future<void> _mostrarGuia() {
    FocusManager.instance.primaryFocus?.unfocus();
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gFecha,
        icono: Icons.event,
        titulo: tr('Fecha y hora de compra', 'Purchase date & time'),
        texto: tr(
          'Es el dato más importante y se llena solo. Si anotas la compra más tarde, tócala y pon la fecha y hora reales: el código usa esta fecha.',
          'The most important field — filled in automatically. If you log the purchase later, tap it to enter the actual date and time: the code uses this date.',
        ),
      ),
      PasoGuia(
        clave: _gVendedor,
        icono: Icons.person_outline,
        titulo: tr('Vendedor', 'Seller'),
        texto: tr(
          'A quién se lo compraste. Al escribir, CataLog te sugiere los vendedores que ya usaste.',
          'Who you bought it from. As you type, CataLog suggests sellers you have used before.',
        ),
      ),
      PasoGuia(
        clave: _gLugar,
        icono: Icons.place_outlined,
        titulo: tr('Lugar y GPS', 'Place & GPS'),
        texto: tr(
          'Escribe el lugar; el GPS se guarda solo, aunque no haya señal. Si salió mal, toca "Actualizar".',
          'Enter the location; GPS coordinates are saved automatically, even offline. Tap "Update" to refresh.',
        ),
      ),
      PasoGuia(
        clave: _gPrecio,
        icono: Icons.payments_outlined,
        titulo: tr('Precio pagado', 'Price paid'),
        texto: tr(
          'En pesos, sin decimales. No sale en el sticker: solo lo ves tú en la app.',
          'In pesos, no decimals. Never printed on the sticker: only visible to you in the app.',
        ),
      ),
      PasoGuia(
        clave: _gTipo,
        icono: Icons.category_outlined,
        titulo: tr('Tipo de catalítico', 'Converter type'),
        texto: tr(
          'Elige el motor y el material. Si eliges DPF, el motor queda en diésel.',
          'Choose engine and material. Selecting DPF automatically sets the engine to diesel.',
        ),
      ),
      PasoGuia(
        clave: _gFabrica,
        icono: Icons.tag,
        titulo: tr('Código de fábrica y autos', 'Factory code & vehicles'),
        texto: tr(
          'El código grabado en la pieza y de qué autos es. Sirven para buscarlo después en el historial.',
          'The code stamped on the shell and compatible vehicles. Useful for searching in history later.',
        ),
      ),
      PasoGuia(
        clave: _gFoto,
        icono: Icons.photo_camera_outlined,
        titulo: tr('Foto', 'Photo'),
        texto: tr(
          'Una foto del catalítico queda guardada en su ficha, como respaldo.',
          'A photo of the converter stays attached to its record as proof.',
        ),
      ),
      PasoGuia(
        clave: _gGuardar,
        icono: Icons.check_circle_outline,
        titulo: tr('Guardar', 'Save'),
        texto: tr(
          'Al guardar se crea el código único y se abre la ficha, lista para imprimir el sticker.',
          'Saving generates the unique code and opens the record, ready to print its sticker.',
        ),
      ),
    ]);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    if (e != null) {
      _fecha = e.fechaCompra;
      _vendedor.text = e.vendedor;
      _lugar.text = e.lugar;
      _precio.text = miles(e.precio);
      _codigoFabrica.text = e.codigoFabrica;
      _autos.text = e.autos;
      _notas.text = e.notas;
      _motor = e.motor;
      _material = e.material;
      _lat = e.lat;
      _lng = e.lng;
      _precision = e.precisionM;
      _foto = e.fotoPath;
      _fotoOriginal = e.fotoPath;
    } else {
      _fecha = alMinuto(DateTime.now());
    }
    for (final c in [_vendedor, _lugar, _precio, _codigoFabrica, _autos, _notas]) {
      c.addListener(_marcarSucio);
    }
    _codigoFabrica.addListener(_buscarReferencia);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarSugerencias();
      _buscarReferencia();
      if (!_editando) _tomarGps();
    });
  }

  void _marcarSucio() => _sucio = true;

  FotosStore? _fotosStore;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fotosStore = AppScope.of(context).fotos;
  }

  @override
  void dispose() {
    // Si se tomó una foto y no se guardó la compra, se borra para no dejar basura.
    if (!_terminado && _fotoNuevaSinGuardar != null) {
      _fotosStore?.borrar(_fotoNuevaSinGuardar);
    }
    for (final c in [_vendedor, _lugar, _precio, _codigoFabrica, _autos, _notas]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarSugerencias() async {
    final repo = AppScope.of(context).compras;
    List<String> v, l, a, cf;
    try {
      v = await repo.sugerencias('vendedor');
      l = await repo.sugerencias('lugar');
      a = await repo.sugerencias('autos');
      cf = await repo.sugerencias('codigo_fabrica');
    } catch (_) {
      return; // sin sugerencias no pasa nada
    }
    if (mounted) {
      setState(() {
        _vendedores = v;
        _lugares = l;
        _autosUsados = a;
        _codigosFabrica = cf;
      });
    }
  }

  int _consultaRef = 0;

  Future<void> _buscarReferencia() async {
    if (!mounted) return;
    final alcance = AppScope.maybeOf(context);
    if (alcance == null) return;
    final texto = _codigoFabrica.text.trim();
    if (texto.length < 2) {
      if (_referencia != null && mounted) setState(() => _referencia = null);
      return;
    }
    final ticket = ++_consultaRef;
    try {
      final ref = await alcance.compras.referenciaCodigoFabrica(texto, excluirId: widget.existente?.id);
      if (!mounted || ticket != _consultaRef) return;
      setState(() => _referencia = ref);
    } catch (_) {}
  }

  void _usarReferencia(ReferenciaPrecio ref) {
    final textoPrecio = miles(ref.ultimoPrecio);
    _precio.value = TextEditingValue(
      text: textoPrecio,
      selection: TextSelection.collapsed(offset: textoPrecio.length),
    );
    if (_autos.text.trim().isEmpty && ref.ultimoAutos.isNotEmpty) {
      _autos.text = ref.ultimoAutos;
    }
    setState(() => _sucio = true);
  }

  Future<void> _tomarGps() async {
    setState(() {
      _buscandoGps = true;
      _errorGps = null;
    });
    final r = await leerUbicacion();
    if (!mounted) return;
    setState(() {
      _buscandoGps = false;
      if (r.ok) {
        _lat = r.lat;
        _lng = r.lng;
        _precision = r.precisionM;
        if (_editando) _sucio = true;
      } else {
        _errorGps = r.error;
      }
    });
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: _fecha.isAfter(ahora) ? ahora : _fecha,
      firstDate: DateTime(2015),
      lastDate: ahora,
      helpText: tr('Fecha de compra', 'Purchase date'),
    );
    if (dia == null || !mounted) return;
    final h = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
      helpText: tr('Hora de compra', 'Purchase time'),
    );
    if (!mounted) return;
    setState(() {
      _fecha = DateTime(dia.year, dia.month, dia.day, h?.hour ?? _fecha.hour, h?.minute ?? _fecha.minute);
      _errorFecha = validarFechaCompra(_fecha, DateTime.now());
      _sucio = true;
    });
  }

  Future<void> _tomarFoto() async {
    final fotos = AppScope.of(context).fotos;
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );
      if (x == null) return;
      final relativa = await fotos.guardar(x.path);
      if (_fotoNuevaSinGuardar != null) await fotos.borrar(_fotoNuevaSinGuardar);
      if (!mounted) return;
      setState(() {
        _foto = relativa;
        _fotoNuevaSinGuardar = relativa;
        _sucio = true;
      });
    } catch (e) {
      if (mounted) avisar(context, '${tr('No se pudo usar la cámara', 'Could not use camera')}: $e');
    }
  }

  Future<void> _quitarFoto() async {
    if (_fotoNuevaSinGuardar != null && _fotoNuevaSinGuardar == _foto) {
      await AppScope.of(context).fotos.borrar(_fotoNuevaSinGuardar);
      _fotoNuevaSinGuardar = null;
    }
    setState(() {
      _foto = null;
      _sucio = true;
    });
  }

  Future<void> _guardar() async {
    final errFecha = validarFechaCompra(_fecha, DateTime.now());
    final errTipo = (_motor == null || _material == null)
        ? tr('Elige el motor y el material', 'Choose engine and material')
        : null;
    final formOk = _form.currentState!.validate();
    setState(() {
      _errorFecha = errFecha;
      _errorTipo = errTipo;
    });
    if (!formOk || errFecha != null || errTipo != null) {
      avisar(context, tr('Revisa los campos marcados en rojo', 'Check the fields highlighted in red'));
      return;
    }

    setState(() => _guardando = true);
    final scope = AppScope.of(context);
    final navegador = Navigator.of(context);
    final datos = DatosCompra(
      fechaCompra: _fecha,
      vendedor: _vendedor.text,
      lugar: _lugar.text,
      lat: _lat,
      lng: _lng,
      precisionM: _precision,
      precio: parseClp(_precio.text) ?? 0,
      motor: _motor!,
      material: _material!,
      codigoFabrica: _codigoFabrica.text,
      autos: _autos.text,
      fotoPath: _foto,
      notas: _notas.text,
    );
    try {
      if (_editando) {
        await scope.compras.actualizar(widget.existente!.id, datos);
        if (_fotoOriginal != null && _fotoOriginal != _foto) {
          await scope.fotos.borrar(_fotoOriginal);
        }
        _terminado = true;
        navegador.pop(true);
      } else {
        final nueva = await scope.compras.crear(datos);
        _terminado = true;
        navegador.pushReplacement(MaterialPageRoute(
          builder: (_) => FichaScreen(id: nueva.id, recienCreada: true),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      avisar(context, e is DatosInvalidos ? e.mensaje : '${tr('No se pudo guardar', 'Could not save')}: $e');
    }
  }

  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Salir sin guardar?', 'Leave without saving?')),
        content: Text(tr('Se perderá lo que escribiste en esta compra.', 'Changes to this purchase will be lost.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Seguir editando', 'Keep editing'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Salir', 'Leave'))),
        ],
      ),
    );
    if (salir == true && mounted) {
      setState(() => _sucio = false);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sucio || _terminado,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarSalida();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editando ? tr('Corregir compra', 'Edit purchase') : tr('Nueva compra', 'New purchase')),
          actions: [BotonAyuda(alTocar: _mostrarGuia)],
        ),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye todo el formulario, para la guía
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                KeyedSubtree(key: _gFecha, child: _tarjetaFecha()),
                const SizedBox(height: 16),
                CampoAutocompletar(
                  key: _gVendedor,
                  controller: _vendedor,
                  etiqueta: tr('Vendedor', 'Seller'),
                  opciones: _vendedores,
                  icono: Icons.person_outline,
                  mayusculas: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? tr('Escribe a quién se lo compraste', 'Enter the seller name') : null,
                ),
                const SizedBox(height: 12),
                Column(
                  key: _gLugar,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CampoAutocompletar(
                      controller: _lugar,
                      etiqueta: tr('Lugar de compra', 'Purchase location'),
                      ayuda: tr('Feria Agro, taller, domicilio…', 'Market, shop, address…'),
                      opciones: _lugares,
                      icono: Icons.place_outlined,
                    ),
                    _estadoGps(),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: _gPrecio,
                  controller: _precio,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ClpInputFormatter()],
                  style: mono(size: 18),
                  decoration: InputDecoration(
                    labelText: tr('Precio pagado', 'Price paid'),
                    prefixText: r'$ ',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  validator: (v) => parseClp(v ?? '') == null ? tr('Escribe el precio', 'Enter the price') : null,
                ),
                const SizedBox(height: 18),
                KeyedSubtree(key: _gTipo, child: _tipo()),
                const SizedBox(height: 16),
                Column(
                  key: _gFabrica,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CampoAutocompletar(
                      controller: _codigoFabrica,
                      etiqueta: tr('Código grabado de fábrica', 'Factory stamped code'),
                      ayuda: '0D140',
                      opciones: _codigosFabrica,
                      icono: Icons.tag,
                      estilo: mono(size: 16),
                      mayusculas: TextCapitalization.characters,
                    ),
                    if (_referencia != null) _pastillaReferencia(_referencia!),
                  ],
                ),
                const SizedBox(height: 12),
                CampoAutocompletar(
                  controller: _autos,
                  etiqueta: tr('De qué autos es', 'Compatible vehicles'),
                  ayuda: 'Toyota Yaris 2008-2013',
                  opciones: _autosUsados,
                  icono: Icons.directions_car_outlined,
                ),
                const SizedBox(height: 16),
                KeyedSubtree(key: _gFoto, child: _seccionFoto()),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notas,
                  maxLines: 3,
                  minLines: 2,
                  decoration: InputDecoration(labelText: tr('Notas (opcional)', 'Notes (optional)')),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: _gGuardar,
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_editando ? tr('Guardar cambios', 'Save changes') : tr('Guardar compra', 'Save purchase')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tarjetaFecha() {
    final ahora = DateTime.now();
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _errorFecha != null ? CatalogColors.rojo : CatalogColors.naranja,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _elegirFecha,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.event, color: CatalogColors.naranja, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Fecha y hora de compra', 'Purchase date & time'), style: etiqueta),
                    Text(fechaCompraCorta(_fecha, ahora),
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                    Text(capitalizar(fechaLarga(_fecha)), style: etiqueta),
                    if (_errorFecha != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_errorFecha!,
                            style: TextStyle(color: CatalogColors.rojo, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              Text(tr('Cambiar', 'Change'),
                  style: TextStyle(color: CatalogColors.texto, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoGps() {
    Widget fila(IconData icono, Color color, String texto, {String? accion}) => Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Row(
            children: [
              Icon(icono, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(texto, style: TextStyle(fontSize: 13, color: color))),
              if (accion != null)
                TextButton(onPressed: _buscandoGps ? null : _tomarGps, child: Text(accion)),
            ],
          ),
        );

    if (_buscandoGps) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(tr('Buscando ubicación GPS…', 'Getting GPS location…'), style: etiqueta),
          ],
        ),
      );
    }
    if (_lat != null) {
      final prec = _precision == null ? '' : ' (±${_precision!.round()} m)';
      return fila(Icons.check_circle, CatalogColors.verde,
          '${tr('Ubicación GPS guardada', 'GPS location saved')}$prec',
          accion: tr('Actualizar', 'Update'));
    }
    if (_errorGps != null) {
      return fila(Icons.warning_amber, CatalogColors.rojo, _errorGps!, accion: tr('Reintentar', 'Retry'));
    }
    return fila(Icons.location_off_outlined, CatalogColors.acero, tr('Sin ubicación GPS', 'No GPS location'),
        accion: tr('Tomar GPS', 'Get GPS'));
  }

  Widget _tipo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Motor', 'Engine'), style: etiqueta),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<Motor>(
            segments: [
              for (final m in Motor.values) ButtonSegment(value: m, label: Text(m.etiqueta)),
            ],
            selected: _motor == null ? <Motor>{} : {_motor!},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _motor = s.isEmpty ? null : s.first;
              // Los DPF son solo de motores diésel.
              if (_motor == Motor.bencinero && _material == TipoMaterial.dpf) _material = null;
              _sucio = true;
            }),
          ),
        ),
        const SizedBox(height: 12),
        Text(tr('Material', 'Material'), style: etiqueta),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TipoMaterial>(
            segments: [
              for (final t in TipoMaterial.values) ButtonSegment(value: t, label: Text(t.etiqueta)),
            ],
            selected: _material == null ? <TipoMaterial>{} : {_material!},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _material = s.isEmpty ? null : s.first;
              if (_material == TipoMaterial.dpf) _motor = Motor.diesel;
              _sucio = true;
            }),
          ),
        ),
        const SizedBox(height: 6),
        if (_errorTipo != null)
          Text(_errorTipo!, style: TextStyle(color: CatalogColors.rojo, fontSize: 13)),
      ],
    );
  }

  Widget _pastillaReferencia(ReferenciaPrecio ref) {
    final n = ref.cantidad;
    final veces = n == 1 ? tr('1 compra anterior', '1 past purchase') : tr('$n compras anteriores', '$n past purchases');
    final rango = n > 1 && ref.minimo != ref.maximo ? ' · ${clp(ref.minimo)}–${clp(ref.maximo)}' : '';
    final precioActual = parseClp(_precio.text);
    final mostrarUsar = precioActual != ref.ultimoPrecio;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: CatalogColors.naranjaClara,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: mostrarUsar ? () => _usarReferencia(ref) : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                const Icon(Icons.history, size: 20, color: CatalogColors.naranja),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${tr('Última vez', 'Last time')}: ${clp(ref.ultimoPrecio)}'
                        '${n > 1 ? ' · ${tr('prom.', 'avg')} ${clp(ref.promedio)}' : ''}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '$veces (${fechaCorta(ref.ultimaFecha)})$rango',
                        style: etiqueta.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (mostrarUsar) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: CatalogColors.naranja,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      tr('Usar ${clp(ref.ultimoPrecio)}', 'Use ${clp(ref.ultimoPrecio)}'),
                      style: const TextStyle(
                        color: CatalogColors.marino,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seccionFoto() {
    final foto = _foto;
    if (foto == null) {
      return OutlinedButton.icon(
        onPressed: _tomarFoto,
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text(tr('Tomar foto del catalítico', 'Take photo of converter')),
      );
    }
    final archivo = AppScope.of(context).fotos.archivo(foto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(File(archivo.path), height: 200, fit: BoxFit.cover),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _tomarFoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Cambiar foto', 'Change photo')),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _quitarFoto,
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('Quitar', 'Remove')),
            ),
          ],
        ),
      ],
    );
  }
}
