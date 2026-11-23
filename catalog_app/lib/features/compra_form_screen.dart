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
import '../theme.dart';
import '../widgets/campo_autocompletar.dart';
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

  bool get _editando => widget.existente != null;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cargarSugerencias();
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
    List<String> v, l, a;
    try {
      v = await repo.sugerencias('vendedor');
      l = await repo.sugerencias('lugar');
      a = await repo.sugerencias('autos');
    } catch (_) {
      return; // sin sugerencias no pasa nada
    }
    if (mounted) {
      setState(() {
        _vendedores = v;
        _lugares = l;
        _autosUsados = a;
      });
    }
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
      helpText: 'Fecha de compra',
    );
    if (dia == null || !mounted) return;
    final h = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
      helpText: 'Hora de compra',
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
      if (mounted) avisar(context, 'No se pudo usar la cámara: $e');
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
    final errTipo = (_motor == null || _material == null) ? 'Elige el motor y el material' : null;
    final formOk = _form.currentState!.validate();
    setState(() {
      _errorFecha = errFecha;
      _errorTipo = errTipo;
    });
    if (!formOk || errFecha != null || errTipo != null) {
      avisar(context, 'Revisa los campos marcados en rojo');
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
      avisar(context, e is DatosInvalidos ? e.mensaje : 'No se pudo guardar: $e');
    }
  }

  Future<void> _confirmarSalida() async {
    final salir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Se perderá lo que escribiste en esta compra.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Seguir editando')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
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
        appBar: AppBar(title: Text(_editando ? 'Corregir compra' : 'Nueva compra')),
        body: SafeArea(
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _tarjetaFecha(),
                const SizedBox(height: 16),
                CampoAutocompletar(
                  controller: _vendedor,
                  etiqueta: 'Vendedor',
                  opciones: _vendedores,
                  icono: Icons.person_outline,
                  mayusculas: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Escribe a quién se lo compraste' : null,
                ),
                const SizedBox(height: 12),
                CampoAutocompletar(
                  controller: _lugar,
                  etiqueta: 'Lugar de compra',
                  ayuda: 'Feria Agro, taller, domicilio…',
                  opciones: _lugares,
                  icono: Icons.place_outlined,
                ),
                _estadoGps(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _precio,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ClpInputFormatter()],
                  style: mono(size: 18),
                  decoration: const InputDecoration(
                    labelText: 'Precio pagado',
                    prefixText: r'$ ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (v) => parseClp(v ?? '') == null ? 'Escribe el precio' : null,
                ),
                const SizedBox(height: 18),
                _tipo(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codigoFabrica,
                  textCapitalization: TextCapitalization.characters,
                  style: mono(size: 16),
                  decoration: const InputDecoration(
                    labelText: 'Código grabado de fábrica',
                    hintText: '0D140',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 12),
                CampoAutocompletar(
                  controller: _autos,
                  etiqueta: 'De qué autos es',
                  ayuda: 'Toyota Yaris 2008-2013',
                  opciones: _autosUsados,
                  icono: Icons.directions_car_outlined,
                ),
                const SizedBox(height: 16),
                _seccionFoto(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notas,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_editando ? 'Guardar cambios' : 'Guardar compra'),
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
                    const Text('Fecha y hora de compra', style: etiqueta),
                    Text(fechaCompraCorta(_fecha, ahora),
                        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                    Text(capitalizar(fechaLarga(_fecha)), style: etiqueta),
                    if (_errorFecha != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_errorFecha!,
                            style: const TextStyle(color: CatalogColors.rojo, fontSize: 13)),
                      ),
                  ],
                ),
              ),
              const Text('Cambiar',
                  style: TextStyle(color: CatalogColors.marino, fontWeight: FontWeight.w500)),
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
      return const Padding(
        padding: EdgeInsets.only(top: 8, left: 4),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Buscando ubicación GPS…', style: etiqueta),
          ],
        ),
      );
    }
    if (_lat != null) {
      final prec = _precision == null ? '' : ' (±${_precision!.round()} m)';
      return fila(Icons.check_circle, CatalogColors.verde, 'Ubicación GPS guardada$prec',
          accion: 'Actualizar');
    }
    if (_errorGps != null) {
      return fila(Icons.warning_amber, CatalogColors.rojo, _errorGps!, accion: 'Reintentar');
    }
    return fila(Icons.location_off_outlined, CatalogColors.acero, 'Sin ubicación GPS',
        accion: 'Tomar GPS');
  }

  Widget _tipo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Motor', style: etiqueta),
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
        const Text('Material', style: etiqueta),
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
          Text(_errorTipo!, style: const TextStyle(color: CatalogColors.rojo, fontSize: 13)),
      ],
    );
  }

  Widget _seccionFoto() {
    final foto = _foto;
    if (foto == null) {
      return OutlinedButton.icon(
        onPressed: _tomarFoto,
        icon: const Icon(Icons.photo_camera_outlined),
        label: const Text('Tomar foto del catalítico'),
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
              label: const Text('Cambiar foto'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _quitarFoto,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Quitar'),
            ),
          ],
        ),
      ],
    );
  }
}
