import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../domain/codigo.dart';
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
    if (!mounted) return;
    setState(() {
      _prefijo.text = p ?? prefijoPorDefecto;
      _nombre.text = n ?? '';
    });
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final repo = AppScope.of(context).compras;
    await repo.guardarAjuste('prefijo', normalizarPrefijo(_prefijo.text));
    await repo.guardarAjuste('nombre', _nombre.text.trim());
    if (mounted) {
      avisar(context, 'Ajustes guardados');
      Navigator.of(context).pop();
    }
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
            padding: const EdgeInsets.all(16),
            children: [
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
              const SizedBox(height: 24),
              FilledButton(onPressed: _guardar, child: const Text('Guardar')),
              const SizedBox(height: 32),
              const Text('CataLog · versión 0.2 (registro de compras)', style: etiqueta),
              const Text('Los datos se guardan solo en este teléfono.', style: etiqueta),
            ],
          ),
        ),
      ),
    );
  }
}
