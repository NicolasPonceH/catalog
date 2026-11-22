import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
import '../printing/etiqueta.dart';
import '../printing/impresora.dart';
import '../printing/imprimir.dart';
import '../theme.dart';

class AjustesScreen extends StatefulWidget {
  const AjustesScreen({super.key});

  @override
  State<AjustesScreen> createState() => _AjustesScreenState();
}

class _AjustesScreenState extends State<AjustesScreen> {
  final _form = GlobalKey<FormState>();
  final _prefijo = TextEditingController();
  final _nombre = TextEditingController();
  bool _cargado = false;

  ImpresoraGuardada? _impresora;
  bool _buscando = false;
  String _ancho = '58';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_cargado) {
      _cargado = true;
      _cargar();
    }
  }

  Future<void> _cargar() async {
    final repo = AppScope.of(context).compras;
    final p = await repo.leerAjuste('prefijo');
    final n = await repo.leerAjuste('nombre');
    final imp = ImpresoraGuardada.deTexto(await repo.leerAjuste(claveImpresora));
    final ancho = await repo.leerAjuste(claveAnchoPapel);
    if (!mounted) return;
    setState(() {
      _prefijo.text = p ?? prefijoPorDefecto;
      _nombre.text = n ?? '';
      _impresora = imp;
      _ancho = ancho ?? '58';
    });
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final repo = AppScope.of(context).compras;
    await repo.guardarAjuste('prefijo', normalizarPrefijo(_prefijo.text));
    await repo.guardarAjuste('nombre', _nombre.text.trim());
    if (mounted) avisar(context, 'Ajustes guardados');
  }

  Future<void> _elegirImpresora() async {
    final repo = AppScope.of(context).compras;
    setState(() => _buscando = true);
    List<ImpresoraEncontrada> lista;
    try {
      lista = await Impresora.buscar();
    } on ErrorImpresora catch (e) {
      if (mounted) avisar(context, e.mensaje);
      return;
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
    if (!mounted) return;
    final elegida = await showModalBottomSheet<ImpresoraEncontrada>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: lista.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No se encontró ningún equipo. Enciende la impresora y acércala al teléfono. '
                    'Si es una impresora "clásica", emparéjala primero en Ajustes de Android > '
                    'Bluetooth (el PIN suele ser 0000 o 1234).',
                    style: TextStyle(fontSize: 15, height: 1.4),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text('Elige la impresora',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                    ),
                    for (final b in lista)
                      ListTile(
                        leading: Icon(b.pareceImpresora ? Icons.print_outlined : Icons.bluetooth),
                        title: Text(b.nombre.isEmpty ? 'Sin nombre' : b.nombre),
                        subtitle: Text(
                          '${b.conexion == Conexion.clasica ? 'Bluetooth clásico (emparejada)' : 'Bluetooth BLE'}'
                          ' · ${b.id}',
                          style: etiqueta,
                        ),
                        onTap: () => Navigator.pop(context, b),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    setState(() => _buscando = true);
    try {
      final imp = await Impresora.preparar(elegida);
      await repo.guardarAjuste(claveImpresora, imp.aTexto());
      if (!mounted) return;
      setState(() => _impresora = imp);
      avisar(context, '${imp.nombre} lista (${imp.descripcion}). Imprime una prueba.');
    } on ErrorImpresora catch (e) {
      if (mounted) avisar(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _cambiarAncho(String ancho) async {
    await AppScope.of(context).compras.guardarAjuste(claveAnchoPapel, ancho);
    setState(() => _ancho = ancho);
  }

  Future<void> _imprimirPrueba() async {
    final prefijo = normalizarPrefijo(_prefijo.text.isEmpty ? prefijoPorDefecto : _prefijo.text);
    await imprimirSticker(
      context,
      DatosEtiqueta(
        codigo: '$prefijo-000000-0000',
        fechaCompra: DateTime.now(),
        tipo: 'Sticker de prueba',
      ),
    );
  }

  @override
  void dispose() {
    _prefijo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              const _Titulo('Este teléfono'),
              TextFormField(
                controller: _nombre,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quién usa este teléfono',
                  hintText: 'Tu nombre',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _prefijo,
                textCapitalization: TextCapitalization.characters,
                style: mono(size: 18),
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'Prefijo de los códigos',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => validarPrefijo(v ?? ''),
              ),
              const Text(
                'Los códigos nuevos empiezan con este prefijo, por ejemplo '
                'CTL-261121-0001. Usa uno distinto en cada teléfono (por ejemplo '
                'CTL y CTT) para que nunca se repitan. Los códigos que ya existen '
                'no cambian.',
                style: TextStyle(fontSize: 14, height: 1.4, color: CatalogColors.acero),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _guardar, child: const Text('Guardar')),

              const SizedBox(height: 32),
              const _Titulo('Impresora de stickers'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.print_outlined),
                  title: Text(_impresora == null
                      ? 'Ninguna elegida'
                      : _impresora!.nombre.isNotEmpty ? _impresora!.nombre : 'Impresora'),
                  subtitle: _impresora == null ? null : Text(_impresora!.descripcion, style: etiqueta),
                  trailing: _buscando
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: _elegirImpresora,
                          child: Text(_impresora == null ? 'Buscar' : 'Cambiar'),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Ancho del papel', style: etiqueta),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '58', label: Text('58 mm')),
                    ButtonSegment(value: '80', label: Text('80 mm')),
                  ],
                  selected: {_ancho},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _cambiarAncho(s.first),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _buscando ? null : (_impresora == null ? _elegirImpresora : _imprimirPrueba),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Imprimir sticker de prueba'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Funciona con impresoras térmicas Bluetooth clásicas, BLE y las mini impresoras '
                'de AliExpress (las de apps como iPrint o Fun Print). CataLog detecta el tipo solo. '
                'Las clásicas se emparejan primero en Ajustes de Android > Bluetooth (PIN 0000 o 1234). '
                'Si un equipo aparece dos veces y uno no imprime, prueba con el otro. '
                'Para que el sticker pegue, usa rollos térmicos adhesivos.',
                style: TextStyle(fontSize: 14, height: 1.4, color: CatalogColors.acero),
              ),

              const SizedBox(height: 32),
              const Text('CataLog · versión 1.0', style: etiqueta),
              const Text('Los datos se guardan solo en este teléfono.', style: etiqueta),
            ],
          ),
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(texto, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}
