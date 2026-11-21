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

  String? _impresoraNombre;
  String? _impresoraMac;
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
    final mac = await repo.leerAjuste(claveImpresoraMac);
    final nom = await repo.leerAjuste(claveImpresoraNombre);
    final ancho = await repo.leerAjuste(claveAnchoPapel);
    if (!mounted) return;
    setState(() {
      _prefijo.text = p ?? prefijoPorDefecto;
      _nombre.text = n ?? '';
      _impresoraMac = mac;
      _impresoraNombre = nom;
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
    List<ImpresoraBt> lista;
    try {
      lista = await Impresora.emparejadas();
    } on ErrorImpresora catch (e) {
      if (mounted) avisar(context, e.mensaje);
      return;
    }
    if (!mounted) return;
    final elegida = await showModalBottomSheet<ImpresoraBt>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: lista.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No hay equipos Bluetooth emparejados. Enciende la impresora, ve a '
                  'Ajustes de Android > Bluetooth, emparéjala (el PIN suele ser 0000 o 1234) '
                  'y vuelve a intentar.',
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text('Elige la impresora', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                  ),
                  for (final b in lista)
                    ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(b.nombre.isEmpty ? 'Sin nombre' : b.nombre),
                      subtitle: Text(b.mac, style: mono(size: 12, weight: FontWeight.w400)),
                      onTap: () => Navigator.pop(context, b),
                    ),
                ],
              ),
      ),
    );
    if (elegida == null) return;
    await repo.guardarAjuste(claveImpresoraMac, elegida.mac);
    await repo.guardarAjuste(claveImpresoraNombre, elegida.nombre);
    setState(() {
      _impresoraMac = elegida.mac;
      _impresoraNombre = elegida.nombre;
    });
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
                  title: Text(_impresoraMac == null
                      ? 'Ninguna elegida'
                      : (_impresoraNombre?.isNotEmpty ?? false) ? _impresoraNombre! : 'Impresora'),
                  subtitle: _impresoraMac == null ? null : Text(_impresoraMac!, style: etiqueta),
                  trailing: TextButton(onPressed: _elegirImpresora, child: const Text('Elegir')),
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
                onPressed: _impresoraMac == null ? _elegirImpresora : _imprimirPrueba,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Imprimir sticker de prueba'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Primero empareja la impresora en Ajustes de Android > Bluetooth '
                '(el PIN suele ser 0000 o 1234). Para que el sticker pegue, usa rollos '
                'térmicos adhesivos.',
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
