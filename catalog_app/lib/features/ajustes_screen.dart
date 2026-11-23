import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/dispositivo.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../printing/etiqueta.dart';
import '../printing/impresora.dart';
import '../printing/imprimir.dart';
import '../system/bloqueo.dart';
import '../theme.dart';
import '../version.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'inicio_screen.dart';
import 'presentacion_screen.dart';
import 'traspaso.dart';

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
  bool _bloqueo = false;

  AjustesDispositivo? get _dispositivo => AppScope.of(context).dispositivo;

  // Partes que ilumina la guía.
  final _gNombre = GlobalKey();
  final _gImpresora = GlobalKey();
  final _gPapel = GlobalKey();
  final _gPrueba = GlobalKey();
  final _gSeguridad = GlobalKey();
  final _gRespaldo = GlobalKey();
  final _gPresentacion = GlobalKey();

  Future<void> _mostrarGuia() {
    FocusManager.instance.primaryFocus?.unfocus();
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gNombre,
        icono: Icons.badge_outlined,
        titulo: 'Tu nombre y prefijo',
        texto: 'El nombre sale en el saludo y en los Excel. El prefijo inicia tus códigos: usa uno '
            'distinto en cada teléfono para que nunca se repitan.',
      ),
      PasoGuia(
        clave: _gImpresora,
        icono: Icons.print_outlined,
        titulo: 'Tu impresora',
        texto: 'Enciéndela, toca Buscar y elígela. CataLog detecta solo si es clásica, BLE o de las mini de AliExpress.',
      ),
      PasoGuia(
        clave: _gPapel,
        icono: Icons.straighten,
        titulo: 'Ancho del papel',
        texto: 'El de tu rollo: 58 mm (el más común) u 80 mm.',
      ),
      PasoGuia(
        clave: _gPrueba,
        icono: Icons.receipt_long_outlined,
        titulo: 'Sticker de prueba',
        texto: 'Imprime uno de prueba para confirmar que la impresora funciona.',
      ),
      PasoGuia(
        clave: _gSeguridad,
        icono: Icons.fingerprint,
        titulo: 'Huella al abrir',
        texto: 'Si lo activas, CataLog pide tu huella o PIN al abrirla y después de 2 minutos fuera de la app.',
      ),
      PasoGuia(
        clave: _gRespaldo,
        icono: Icons.backup_outlined,
        titulo: 'Respaldo',
        texto: 'Guarda todas tus compras y fotos en Descargas/Respaldo CataLog. Mándalo a tu correo de vez en cuando.',
      ),
      PasoGuia(
        clave: _gPresentacion,
        icono: Icons.slideshow_outlined,
        titulo: 'Ver la presentación',
        texto: 'Vuelve a ver la presentación de CataLog cuando quieras.',
      ),
    ]);
  }

  Future<void> _verPresentacion() async {
    final navegador = Navigator.of(context);
    final verGuia = await abrirPresentacion(navegador);
    if (!mounted) return;
    await _cargar();
    if (verGuia) {
      navegador.popUntil((r) => r.isFirst);
      pedirGuiaInicio.value++;
    }
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
    final scope = AppScope.of(context);
    final p = await scope.compras.leerAjuste('prefijo');
    final n = await scope.compras.leerAjuste('nombre');
    if (!mounted) return;
    final d = scope.dispositivo;
    setState(() {
      _prefijo.text = p ?? prefijoPorDefecto;
      _nombre.text = n ?? '';
      _impresora = ImpresoraGuardada.deTexto(d?.leer(AjustesDispositivo.impresora));
      _ancho = d?.leer(AjustesDispositivo.anchoPapel) ?? '58';
      _bloqueo = d?.activado(AjustesDispositivo.bloqueo) ?? false;
    });
  }

  Future<void> _guardar() async {
    // El formulario está en la hoja de perfil, que ya lo validó al cerrarse.
    final form = _form.currentState;
    if (form != null && !form.validate()) return;
    final repo = AppScope.of(context).compras;
    await repo.guardarAjuste('prefijo', normalizarPrefijo(_prefijo.text));
    await repo.guardarAjuste('nombre', _nombre.text.trim());
    if (mounted) avisar(context, 'Ajustes guardados');
  }

  // ---------- Impresora ----------

  Future<void> _elegirImpresora() async {
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
                      child: Text('Elige la impresora', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
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
      await _dispositivo?.guardar(AjustesDispositivo.impresora, imp.aTexto());
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
    await _dispositivo?.guardar(AjustesDispositivo.anchoPapel, ancho);
    setState(() => _ancho = ancho);
  }

  Future<void> _imprimirPrueba() async {
    final prefijo = normalizarPrefijo(_prefijo.text.isEmpty ? prefijoPorDefecto : _prefijo.text);
    await imprimirSticker(
      context,
      DatosEtiqueta(codigo: '$prefijo-000000-0000', fechaCompra: DateTime.now(), tipo: 'Sticker de prueba'),
    );
  }

  // ---------- Bloqueo ----------

  Future<void> _cambiarBloqueo(bool activar) async {
    if (activar && !await Bloqueo.disponible()) {
      if (mounted) {
        avisar(context, 'Primero configura un bloqueo de pantalla (huella, PIN o patrón) en el teléfono.');
      }
      return;
    }
    final ok = await Bloqueo.desbloquear(activar ? 'Confirma para activar el bloqueo' : 'Confirma para quitar el bloqueo');
    if (!ok) return;
    await _dispositivo?.guardar(AjustesDispositivo.bloqueo, activar ? '1' : '0');
    if (!mounted) return;
    setState(() => _bloqueo = activar);
    avisar(context, activar ? 'CataLog pedirá huella o PIN al abrirse' : 'Bloqueo desactivado');
  }

  @override
  void dispose() {
    _prefijo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  // ---------- Perfil ----------

  /// Nombre y prefijo, en una hoja aparte (la tarjeta de perfil los muestra).
  Future<void> _editarPerfil() async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (hoja) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(hoja).bottom + 20),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tu perfil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Quién usa este teléfono',
                  hintText: 'Tu nombre',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _prefijo,
                textCapitalization: TextCapitalization.characters,
                style: mono(size: 18),
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'Prefijo de los códigos',
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (v) => validarPrefijo(v ?? ''),
              ),
              const SizedBox(height: 8),
              Text(
                'Los códigos nuevos empiezan con este prefijo, por ejemplo CTL-261121-0001. Usa uno '
                'distinto en cada teléfono (por ejemplo CTL y CTT) para que nunca se repitan. Los '
                'códigos que ya existen no cambian.',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: CatalogColors.acero),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (_form.currentState?.validate() ?? false) Navigator.pop(hoja, true);
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (guardado == true) {
      await _guardar();
      if (mounted) setState(() {});
    }
  }

  // ---------- Apariencia y escaneo ----------

  Future<void> _guardarPreferencia(String clave, String? valor) async {
    await _dispositivo?.guardar(clave, valor);
    if (mounted) setState(() {});
  }

  Future<void> _destacarAyuda() async {
    await _guardarPreferencia(AjustesDispositivo.ayudaUsada, null);
    if (mounted) avisar(context, 'El botón de ayuda vuelve a destacarse');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final revision = scope.soloLectura;
    final d = scope.dispositivo;
    final autoRespaldo = d?.fecha(AjustesDispositivo.ultimoAutoRespaldo);
    final autoLugar = d?.leer(AjustesDispositivo.lugarAutoRespaldo) ?? 'Descargas/Respaldo CataLog';
    final nombre = _nombre.text.trim();
    final iniciales = nombre.isEmpty
        ? ''
        : nombre.split(RegExp(r'\s+')).take(2).map((p) => p.characters.first.toUpperCase()).join();
    final letra = d?.escalaLetra ?? 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      body: SafeArea(
        child: ListView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye toda la pantalla, para la guía
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: [
            // ---- Perfil ----
            Material(
              key: _gNombre,
              color: CatalogColors.marino,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: revision ? null : _editarPerfil,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: CatalogColors.naranja, shape: BoxShape.circle),
                        child: iniciales.isEmpty
                            ? const Icon(Icons.person, color: CatalogColors.marino, size: 28)
                            : Text(iniciales,
                                style: const TextStyle(
                                    color: CatalogColors.marino, fontSize: 19, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nombre.isEmpty ? 'Tu nombre' : nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: CatalogColors.niebla, fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              revision
                                  ? 'Sesión de revisión: ${scope.sesion?.nombre ?? ''}'
                                  : 'Prefijo ${normalizarPrefijo(_prefijo.text)} · Mis compras',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (!revision) const Icon(Icons.edit_outlined, color: CatalogColors.niebla, size: 20),
                    ],
                  ),
                ),
              ),
            ),

            // ---- Apariencia ----
            _Seccion(
              titulo: 'Apariencia',
              hijos: [
                _Fila(
                  icono: Icons.palette_outlined,
                  color: const Color(0xFF7F77DD),
                  titulo: 'Tema',
                  abajo: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'claro', label: Text('Claro')),
                        ButtonSegment(value: 'oscuro', label: Text('Oscuro')),
                        ButtonSegment(value: 'auto', label: Text('Auto')),
                      ],
                      selected: {d?.temaElegido ?? 'claro'},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => _guardarPreferencia(AjustesDispositivo.tema, s.first),
                    ),
                  ),
                ),
                _Fila(
                  icono: Icons.contrast,
                  color: const Color(0xFF444441),
                  titulo: 'Alto contraste',
                  subtitulo: 'Textos y bordes más marcados',
                  derecha: Switch(
                    value: d?.activado(AjustesDispositivo.contraste) ?? false,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.contraste, v ? '1' : null),
                  ),
                ),
                _Fila(
                  icono: Icons.text_fields,
                  color: const Color(0xFFD4537E),
                  titulo: 'Tamaño de letra',
                  abajo: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '1.0', label: Text('Normal')),
                        ButtonSegment(value: '1.15', label: Text('Grande')),
                        ButtonSegment(value: '1.3', label: Text('Enorme')),
                      ],
                      selected: {letra >= 1.3 ? '1.3' : (letra >= 1.15 ? '1.15' : '1.0')},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          _guardarPreferencia(AjustesDispositivo.letra, s.first == '1.0' ? null : s.first),
                    ),
                  ),
                ),
                _Fila(
                  icono: Icons.auto_awesome_outlined,
                  color: CatalogColors.naranja,
                  titulo: 'Animaciones',
                  subtitulo: 'Bienvenida, presentación y guía',
                  derecha: Switch(
                    value: !(d?.activado(AjustesDispositivo.sinAnimaciones) ?? false),
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinAnimaciones, v ? null : '1'),
                  ),
                ),
              ],
            ),

            // ---- Escaneo ----
            _Seccion(
              titulo: 'Al escanear',
              hijos: [
                _Fila(
                  icono: Icons.vibration,
                  color: const Color(0xFFD85A30),
                  titulo: 'Vibrar',
                  derecha: Switch(
                    value: d?.vibrar ?? true,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinVibrar, v ? null : '1'),
                  ),
                ),
                _Fila(
                  icono: Icons.volume_up_outlined,
                  color: const Color(0xFF378ADD),
                  titulo: 'Sonido',
                  derecha: Switch(
                    value: d?.sonar ?? true,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinSonido, v ? null : '1'),
                  ),
                ),
              ],
            ),

            // ---- Impresora ----
            _Seccion(
              titulo: 'Impresora de stickers',
              hijos: [
                _Fila(
                  key: _gImpresora,
                  icono: Icons.print_outlined,
                  color: CatalogColors.marino,
                  titulo: _impresora == null
                      ? 'Ninguna elegida'
                      : (_impresora!.nombre.isNotEmpty ? _impresora!.nombre : 'Impresora'),
                  subtitulo: _impresora?.descripcion ?? 'Enciéndela y toca Buscar',
                  derecha: _buscando
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: _elegirImpresora,
                          child: Text(_impresora == null ? 'Buscar' : 'Cambiar'),
                        ),
                ),
                _Fila(
                  key: _gPapel,
                  icono: Icons.straighten,
                  color: const Color(0xFF1D9E75),
                  titulo: 'Ancho del papel',
                  abajo: SizedBox(
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
                ),
                _Fila(
                  key: _gPrueba,
                  icono: Icons.receipt_long_outlined,
                  color: const Color(0xFFBA7517),
                  titulo: 'Imprimir sticker de prueba',
                  alTocar: _buscando ? null : (_impresora == null ? _elegirImpresora : _imprimirPrueba),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
              ],
              nota: 'Funciona con impresoras térmicas Bluetooth clásicas, BLE y las mini impresoras de '
                  'AliExpress (las de apps como iPrint o Fun Print). CataLog detecta el tipo solo. Las '
                  'clásicas se emparejan primero en Ajustes de Android > Bluetooth (PIN 0000 o 1234).',
            ),

            // ---- Seguridad ----
            _Seccion(
              titulo: 'Seguridad',
              hijos: [
                _Fila(
                  key: _gSeguridad,
                  icono: Icons.fingerprint,
                  color: const Color(0xFF3B6D11),
                  titulo: 'Pedir huella o PIN al abrir',
                  subtitulo: 'Usa el bloqueo del teléfono',
                  derecha: Switch(value: _bloqueo, onChanged: _cambiarBloqueo),
                ),
              ],
            ),

            // ---- Respaldo y traspaso ----
            _Seccion(
              titulo: 'Respaldo y traspaso',
              hijos: [
                if (!revision) ...[
                  Consulta<DateTime?>(
                    cargar: scope.compras.ultimoRespaldo,
                    builder: (context, ultimo) => _Fila(
                      key: _gRespaldo,
                      icono: Icons.backup_outlined,
                      color: const Color(0xFF185FA5),
                      titulo: 'Crear respaldo',
                      subtitulo: ultimo == null ? 'Todavía no has hecho ninguno' : 'Último: ${fechaHora(ultimo)}',
                      alTocar: () => crearRespaldoYEnviar(context),
                      derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                    ),
                  ),
                  _Fila(
                    icono: Icons.send_to_mobile_outlined,
                    color: const Color(0xFF0F6E56),
                    titulo: 'Enviar mis compras a otro celular',
                    alTocar: () => enviarAOtroCelular(context),
                    derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                  ),
                ],
                _Fila(
                  icono: Icons.download_outlined,
                  color: const Color(0xFF534AB7),
                  titulo: 'Recibir datos de otro celular',
                  alTocar: () => recibirDatos(context),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                _Fila(
                  icono: Icons.swap_horiz,
                  color: const Color(0xFF5F5E5A),
                  titulo: 'Cambiar de sesión',
                  subtitulo: 'Ahora: ${scope.sesion?.nombre ?? 'Mis compras'}',
                  alTocar: () => mostrarSesiones(context),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                if (!revision)
                  _Fila(
                    icono: Icons.settings_backup_restore,
                    color: const Color(0xFFA32D2D),
                    titulo: 'Restaurar desde un respaldo',
                    alTocar: () => restaurarDesdeArchivo(context),
                    derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                  ),
              ],
              nota: autoRespaldo == null
                  ? 'Copia automática diaria en $autoLugar: todavía no se ha hecho.'
                  : 'Copia automática diaria: la última fue el ${fechaHora(autoRespaldo)}, en $autoLugar. '
                      'Envía un respaldo a tu correo o Drive de vez en cuando por si se pierde el teléfono.',
            ),

            // ---- Ayuda ----
            _Seccion(
              titulo: 'Ayuda',
              hijos: [
                _Fila(
                  key: _gPresentacion,
                  icono: Icons.slideshow_outlined,
                  color: CatalogColors.naranja,
                  titulo: 'Ver la presentación de nuevo',
                  alTocar: _verPresentacion,
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                _Fila(
                  icono: Icons.help_outline,
                  color: const Color(0xFF378ADD),
                  titulo: 'Volver a destacar el botón de ayuda',
                  subtitulo: 'El signo de pregunta de cada pantalla',
                  alTocar: _destacarAyuda,
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
              ],
            ),

            const SizedBox(height: 26),
            Center(child: Text('CataLog · versión $versionApp · Hecho en Arica', style: etiqueta)),
            Center(child: Text('Los datos se guardan solo en este teléfono.', style: etiqueta)),
          ],
        ),
      ),
    );
  }
}

/// Grupo de ajustes: título, tarjeta con filas separadas por líneas y una nota.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.hijos, this.nota});

  final String titulo;
  final List<Widget> hijos;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
          child: Text(titulo, style: etiqueta.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < hijos.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: CatalogColors.borde),
                hijos[i],
              ],
            ],
          ),
        ),
        if (nota != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(nota!, style: TextStyle(fontSize: 13, height: 1.4, color: CatalogColors.acero)),
          ),
      ],
    );
  }
}

/// Fila de ajuste: ícono en un cuadrito de color, título, subtítulo y un control
/// a la derecha (o debajo, si es ancho).
class _Fila extends StatelessWidget {
  const _Fila({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    this.subtitulo,
    this.derecha,
    this.abajo,
    this.alTocar,
  });

  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final Widget? derecha;
  final Widget? abajo;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: alTocar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icono, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
                      if (subtitulo != null) Text(subtitulo!, style: etiqueta),
                    ],
                  ),
                ),
                ?derecha,
              ],
            ),
            if (abajo != null) ...[
              const SizedBox(height: 10),
              abajo!,
            ],
          ],
        ),
      ),
    );
  }
}
