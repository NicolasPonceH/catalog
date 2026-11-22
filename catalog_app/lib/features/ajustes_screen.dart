import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_scope.dart';
import '../backup/respaldo.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../widgets/consulta.dart';
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
  bool _respaldando = false;
  String _ancho = '58';

  String _dos(int n) => n.toString().padLeft(2, '0');

  Future<void> _respaldar() async {
    final scope = AppScope.of(context);
    setState(() => _respaldando = true);
    try {
      final zip = await armarRespaldo(scope.base, scope.fotos.carpetaBase);
      final pref = await scope.compras.prefijo();
      final t = DateTime.now();
      final nombre = 'CataLog-respaldo-$pref-${t.year}${_dos(t.month)}${_dos(t.day)}-${_dos(t.hour)}${_dos(t.minute)}.zip';
      final archivo = File(p.join((await getTemporaryDirectory()).path, nombre));
      await archivo.writeAsBytes(zip, flush: true);
      final r = await SharePlus.instance.share(ShareParams(
        files: [XFile(archivo.path, mimeType: 'application/zip')],
        text: 'Respaldo de CataLog',
      ));
      if (r.status == ShareResultStatus.dismissed) {
        if (mounted) avisar(context, 'No se envió el respaldo');
      } else {
        await scope.compras.registrarRespaldo();
        if (mounted) avisar(context, 'Respaldo creado. Guárdalo en tu correo o Drive.');
      }
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo crear el respaldo: $e');
    } finally {
      if (mounted) setState(() => _respaldando = false);
    }
  }

  Future<void> _restaurar() async {
    final scope = AppScope.of(context);
    final elegido = await FilePicker.pickFile(type: FileType.any);
    if (elegido == null || !mounted) return;
    ContenidoRespaldo contenido;
    try {
      contenido = leerRespaldo(await elegido.readAsBytes());
    } on RespaldoInvalido catch (e) {
      if (mounted) avisar(context, e.mensaje);
      return;
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo leer el archivo: $e');
      return;
    }
    final actuales = await scope.compras.contarCompras();
    if (!mounted) return;
    final creado = contenido.creado;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar respaldo'),
        content: Text(
          'El respaldo${creado != null ? ' es del ${fechaHora(creado)} y' : ''} tiene '
          '${contenido.compras} compras'
          '${contenido.prefijo.isNotEmpty ? ' (prefijo ${contenido.prefijo})' : ''}.\n\n'
          'Va a reemplazar los datos de este teléfono ($actuales compras). Antes se guarda '
          'una copia de lo actual dentro del teléfono, por si acaso.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final reemplazar = scope.reemplazarDatos;
    if (reemplazar == null) return;
    setState(() => _respaldando = true);
    try {
      await guardarCopiaLocal(await armarRespaldo(scope.base, scope.fotos.carpetaBase), scope.fotos.carpetaBase);
    } catch (e) {
      if (mounted) {
        setState(() => _respaldando = false);
        avisar(context, 'No se pudo guardar la copia de seguridad, no se restauró nada: $e');
      }
      return;
    }
    await reemplazar(
      (ruta) => aplicarRespaldo(contenido, rutaBase: ruta, carpetaBase: scope.fotos.carpetaBase),
      mensaje: 'Datos restaurados: ${contenido.compras} compras',
    );
  }

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
              const _Titulo('Respaldo'),
              Consulta<DateTime?>(
                cargar: AppScope.of(context).compras.ultimoRespaldo,
                builder: (context, ultimo) => Text(
                  ultimo == null ? 'Todavía no se ha hecho ningún respaldo.' : 'Último respaldo: ${fechaHora(ultimo)}',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _respaldando ? null : _respaldar,
                icon: _respaldando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.backup_outlined),
                label: const Text('Crear respaldo y enviarlo'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _respaldando ? null : _restaurar,
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('Restaurar desde un respaldo'),
              ),
              const SizedBox(height: 8),
              const Text(
                'El respaldo es un archivo .zip con todas las compras y sus fotos. Envíalo a tu '
                'correo, Google Drive o WhatsApp. Si cambias o pierdes el teléfono, instala '
                'CataLog en el nuevo y restaura ese archivo.',
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
