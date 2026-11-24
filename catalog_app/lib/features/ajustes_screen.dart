import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/dispositivo.dart';
import '../domain/codigo.dart';
import '../domain/formato.dart';
import '../i18n.dart';
import '../printing/etiqueta.dart';
import '../printing/impresora.dart';
import '../printing/imprimir.dart';
import '../system/bloqueo.dart';
import '../system/notificaciones.dart';
import '../system/sistema.dart';
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
  final _gApariencia = GlobalKey();
  final _gIdioma = GlobalKey();
  final _gNotificaciones = GlobalKey();
  final _gImpresora = GlobalKey();
  final _gPapel = GlobalKey();
  final _gPrueba = GlobalKey();
  final _gSeguridad = GlobalKey();
  final _gUbicarRespaldo = GlobalKey();
  final _gRespaldo = GlobalKey();
  final _gPresentacion = GlobalKey();

  Future<void> _mostrarGuia() {
    FocusManager.instance.primaryFocus?.unfocus();
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gNombre,
        icono: Icons.badge_outlined,
        titulo: tr('Tu nombre y prefijo', 'Your name & prefix'),
        texto: tr(
          'El nombre sale en el saludo y en los Excel. El prefijo inicia tus códigos: usa uno distinto en cada teléfono para que nunca se repitan.',
          'Your name appears in greetings and Excel reports. The prefix starts every code: use a distinct one per phone so codes never collide.',
        ),
      ),
      PasoGuia(
        clave: _gApariencia,
        icono: Icons.palette_outlined,
        titulo: tr('Apariencia y lectura', 'Appearance & readability'),
        texto: tr(
          'Cambia entre modo claro, oscuro o automático, activa el alto contraste y ajusta el tamaño de letra al instante.',
          'Switch between light, dark, or auto mode, enable high contrast, and adjust text size on the fly.',
        ),
      ),
      PasoGuia(
        clave: _gIdioma,
        icono: Icons.translate,
        titulo: tr('Idioma y escaneo', 'Language & scanning'),
        texto: tr(
          'Elige entre Español e Inglés y activa o apaga la vibración y el sonido al escanear.',
          'Choose between Spanish and English and toggle vibration or sound when scanning.',
        ),
      ),
      PasoGuia(
        clave: _gNotificaciones,
        icono: Icons.notifications_active_outlined,
        titulo: tr('Notificaciones locales', 'Local notifications'),
        texto: tr(
          'Funcionan sin internet: avisan cuando se guarda un respaldo y te recuerdan a la hora elegida los stickers pendientes, lotes abiertos, resumen del día y respaldo externo.',
          'Work 100% offline: notify you when backups save and remind you at your chosen time about unprinted stickers, open batches, daily totals, and external backups.',
        ),
      ),
      PasoGuia(
        clave: _gImpresora,
        icono: Icons.print_outlined,
        titulo: tr('Tu impresora', 'Your printer'),
        texto: tr(
          'Enciéndela, toca Buscar y elígela. CataLog detecta solo si es clásica, BLE o de las mini de AliExpress.',
          'Turn it on, tap Search, and select it. CataLog automatically detects classic Bluetooth, BLE, or mini printers.',
        ),
      ),
      PasoGuia(
        clave: _gPapel,
        icono: Icons.straighten,
        titulo: tr('Ancho del papel', 'Paper width'),
        texto: tr(
          'El de tu rollo: 58 mm (el más común) u 80 mm.',
          'Match your thermal roll: 58 mm (most common) or 80 mm.',
        ),
      ),
      PasoGuia(
        clave: _gPrueba,
        icono: Icons.receipt_long_outlined,
        titulo: tr('Sticker de prueba', 'Test sticker'),
        texto: tr(
          'Imprime uno de prueba para confirmar que la impresora funciona.',
          'Print a sample sticker to verify the printer connection.',
        ),
      ),
      PasoGuia(
        clave: _gSeguridad,
        icono: Icons.fingerprint,
        titulo: tr('Huella al abrir', 'Fingerprint lock'),
        texto: tr(
          'Si lo activas, CataLog pide tu huella o PIN al abrirla y después de 2 minutos fuera de la app.',
          'When enabled, CataLog requires your fingerprint or PIN on launch and after 2 minutes in the background.',
        ),
      ),
      PasoGuia(
        clave: _gUbicarRespaldo,
        icono: Icons.folder_special,
        titulo: tr('Ubicar respaldo', 'Locate backup'),
        texto: tr(
          'Te lleva directo en la app de Archivos del teléfono a Descargas/Respaldo CataLog, donde están guardados tus respaldos .zip.',
          'Opens your phone’s Files app directly inside Downloads/Respaldo CataLog, right where your .zip backups live.',
        ),
      ),
      PasoGuia(
        clave: _gRespaldo,
        icono: Icons.backup_outlined,
        titulo: tr('Respaldo', 'Backup'),
        texto: tr(
          'Guarda todas tus compras y fotos en Descargas/Respaldo CataLog. Mándalo a tu correo de vez en cuando.',
          'Saves all your purchases and photos in Downloads/Respaldo CataLog. Email a copy from time to time.',
        ),
      ),
      PasoGuia(
        clave: _gPresentacion,
        icono: Icons.slideshow_outlined,
        titulo: tr('Ver la presentación', 'View walkthrough'),
        texto: tr(
          'Vuelve a ver la presentación de CataLog cuando quieras.',
          'Replay the CataLog intro walkthrough anytime.',
        ),
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
    final form = _form.currentState;
    if (form != null && !form.validate()) return;
    final repo = AppScope.of(context).compras;
    await repo.guardarAjuste('prefijo', normalizarPrefijo(_prefijo.text));
    await repo.guardarAjuste('nombre', _nombre.text.trim());
    if (mounted) avisar(context, tr('Ajustes guardados', 'Settings saved'));
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
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    tr(
                      'No se encontró ningún equipo. Enciende la impresora y acércala al teléfono. Si es una impresora "clásica", emparéjala primero en Ajustes de Android > Bluetooth (el PIN suele ser 0000 o 1234).',
                      'No devices found. Turn on the printer and bring it close to the phone. For classic Bluetooth printers, pair it first in Android Settings > Bluetooth (PIN is usually 0000 or 1234).',
                    ),
                    style: const TextStyle(fontSize: 15, height: 1.4),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                        tr('Elige la impresora', 'Choose printer'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      ),
                    ),
                    for (final b in lista)
                      ListTile(
                        leading: Icon(b.pareceImpresora ? Icons.print_outlined : Icons.bluetooth),
                        title: Text(b.nombre.isEmpty ? tr('Sin nombre', 'Unnamed') : b.nombre),
                        subtitle: Text(
                          '${b.conexion == Conexion.clasica ? tr('Bluetooth clásico (emparejada)', 'Classic Bluetooth (paired)') : 'Bluetooth BLE'}'
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
      avisar(
        context,
        tr(
          '${imp.nombre} lista (${imp.descripcion}). Imprime una prueba.',
          '${imp.nombre} ready (${imp.descripcion}). Print a test sticker.',
        ),
      );
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
      DatosEtiqueta(
        codigo: '$prefijo-000000-0000',
        fechaCompra: DateTime.now(),
        tipo: tr('Sticker de prueba', 'Test sticker'),
      ),
    );
  }

  // ---------- Bloqueo ----------

  Future<void> _cambiarBloqueo(bool activar) async {
    if (activar && !await Bloqueo.disponible()) {
      if (mounted) {
        avisar(
          context,
          tr(
            'Primero configura un bloqueo de pantalla (huella, PIN o patrón) en el teléfono.',
            'First set up a screen lock (fingerprint, PIN, or pattern) on your phone.',
          ),
        );
      }
      return;
    }
    final ok = await Bloqueo.desbloquear(
      activar
          ? tr('Confirma para activar el bloqueo', 'Confirm to enable lock')
          : tr('Confirma para quitar el bloqueo', 'Confirm to disable lock'),
    );
    if (!ok) return;
    await _dispositivo?.guardar(AjustesDispositivo.bloqueo, activar ? '1' : '0');
    if (!mounted) return;
    setState(() => _bloqueo = activar);
    avisar(
      context,
      activar
          ? tr('CataLog pedirá huella o PIN al abrirse', 'CataLog will ask for fingerprint or PIN on launch')
          : tr('Bloqueo desactivado', 'Lock disabled'),
    );
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
              Text(tr('Tu perfil', 'Your profile'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nombre,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('Quién usa este teléfono', 'Who uses this phone'),
                  hintText: tr('Tu nombre', 'Your name'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _prefijo,
                textCapitalization: TextCapitalization.characters,
                style: mono(size: 18),
                maxLength: 5,
                decoration: InputDecoration(
                  labelText: tr('Prefijo de los códigos', 'Code prefix'),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  counterText: '',
                ),
                validator: (v) => validarPrefijo(v ?? ''),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  'Los códigos nuevos empiezan con este prefijo, por ejemplo CTL-261121-0001. Usa uno distinto en cada teléfono (por ejemplo CTL y CTT) para que nunca se repitan. Los códigos que ya existen no cambian.',
                  'New codes start with this prefix, e.g. CTL-261121-0001. Use a distinct prefix per phone (such as CTL and CTT) so they never collide. Existing codes do not change.',
                ),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: CatalogColors.acero),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (_form.currentState?.validate() ?? false) Navigator.pop(hoja, true);
                },
                child: Text(tr('Guardar', 'Save')),
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

  // ---------- Apariencia, idioma y escaneo ----------

  Future<void> _guardarPreferencia(String clave, String? valor) async {
    await _dispositivo?.guardar(clave, valor);
    if (mounted) setState(() {});
  }

  Future<void> _destacarAyuda() async {
    await _guardarPreferencia(AjustesDispositivo.ayudaUsada, null);
    if (mounted) {
      avisar(context, tr('El botón de ayuda vuelve a destacarse', 'Help button highlighted again'));
    }
  }

  Future<void> _elegirHoraRecordatorio() async {
    final d = _dispositivo;
    final (h, m) = d?.horaMinutoRecordatorio ?? (20, 0);
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: h, minute: m),
      helpText: tr('Hora del aviso diario', 'Daily reminder time'),
    );
    if (elegida == null) return;
    final hh = elegida.hour.toString().padLeft(2, '0');
    final mm = elegida.minute.toString().padLeft(2, '0');
    await Sistema.pedirPermisoNotificaciones();
    await _guardarPreferencia(AjustesDispositivo.horaRecordatorio, '$hh:$mm');
    if (mounted) {
      avisar(context, tr('Aviso diario programado a las $hh:$mm', 'Daily reminder scheduled at $hh:$mm'));
    }
  }

  Future<void> _probarNotificacion() async {
    final scope = AppScope.of(context);
    final concedido = await Sistema.pedirPermisoNotificaciones();
    if (!mounted) return;
    final d = scope.dispositivo;
    final resumen = d == null
        ? null
        : await Notificaciones.armarResumenRecordatorio(base: scope.base, dispositivo: d);
    await Sistema.mostrarNotificacion(
      titulo: resumen?.$1 ?? tr('Notificaciones activas · CataLog', 'Notifications active · CataLog'),
      cuerpo: resumen?.$2 ??
          tr(
            'Todo al día: CataLog te avisará al guardar respaldos y en el cierre de jornada.',
            'All caught up: CataLog will notify you when saving backups and at the end of the day.',
          ),
    );
    if (!mounted) return;
    avisar(
      context,
      concedido
          ? tr('Notificación enviada al teléfono', 'Notification sent to your phone')
          : tr(
              'Activa el permiso de notificaciones de CataLog en Ajustes de Android',
              'Enable notification permission for CataLog in Android Settings',
            ),
    );
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
    final temaActual = d?.temaElegido ?? (CatalogColors.paleta.oscura ? 'oscuro' : 'claro');
    final idiomaActual = d?.idiomaElegido ?? Idioma.actual;
    final conBordeTarjeta = CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1;
    final nombreSesion = scope.sesion == null || !scope.sesion!.esRevision
        ? tr('Mis compras', 'My purchases')
        : scope.sesion!.nombre;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Ajustes', 'Settings')),
        actions: [BotonAyuda(alTocar: _mostrarGuia)],
      ),
      body: SafeArea(
        child: ListView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye toda la pantalla, para la guía
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 40),
          children: [
            // ---- Perfil ----
            Container(
              key: _gNombre,
              decoration: BoxDecoration(
                color: CatalogColors.marino,
                borderRadius: BorderRadius.circular(18),
                border: conBordeTarjeta
                    ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
                    : null,
              ),
              child: Material(
                type: MaterialType.transparency,
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
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFFA25C), CatalogColors.naranja],
                            ),
                          ),
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
                                nombre.isEmpty ? tr('Tu nombre', 'Your name') : nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: CatalogColors.niebla, fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                revision
                                    ? '${tr('Sesión de revisión', 'Review session')}: ${scope.sesion?.nombre ?? ''}'
                                    : '${tr('Prefijo', 'Prefix')} ${normalizarPrefijo(_prefijo.text)} · ${tr('Mis compras', 'My purchases')}',
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
            ),

            // ---- Apariencia ----
            _Seccion(
              key: _gApariencia,
              titulo: tr('Apariencia', 'Appearance'),
              hijos: [
                _Fila(
                  icono: Icons.palette_outlined,
                  color: const Color(0xFF7F77DD),
                  titulo: tr('Tema', 'Theme'),
                  abajo: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'claro', label: Text(tr('Claro', 'Light'))),
                        ButtonSegment(value: 'oscuro', label: Text(tr('Oscuro', 'Dark'))),
                        ButtonSegment(value: 'auto', label: Text(tr('Auto', 'Auto'))),
                      ],
                      selected: {temaActual},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => _guardarPreferencia(AjustesDispositivo.tema, s.first),
                    ),
                  ),
                ),
                _Fila(
                  icono: Icons.contrast,
                  color: const Color(0xFF444441),
                  titulo: tr('Alto contraste', 'High contrast'),
                  subtitulo: tr('Textos y bordes más marcados', 'Sharper text and stronger borders'),
                  derecha: Switch(
                    value: d?.activado(AjustesDispositivo.contraste) ?? false,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.contraste, v ? '1' : null),
                  ),
                ),
                _Fila(
                  icono: Icons.text_fields,
                  color: const Color(0xFFD4537E),
                  titulo: tr('Tamaño de letra', 'Text size'),
                  abajo: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: '1.0', label: Text(tr('Normal', 'Normal'))),
                        ButtonSegment(value: '1.15', label: Text(tr('Grande', 'Large'))),
                        ButtonSegment(value: '1.3', label: Text(tr('Enorme', 'Huge'))),
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
                  titulo: tr('Animaciones', 'Animations'),
                  subtitulo: tr('Bienvenida, presentación y guía', 'Welcome screen, intro, and guide'),
                  derecha: Switch(
                    value: !(d?.activado(AjustesDispositivo.sinAnimaciones) ?? false),
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinAnimaciones, v ? null : '1'),
                  ),
                ),
              ],
            ),

            // ---- Idioma y sonido ----
            _Seccion(
              key: _gIdioma,
              titulo: tr('Idioma y sonido', 'Language & sound'),
              hijos: [
                _Fila(
                  icono: Icons.translate,
                  color: const Color(0xFF1D9E75),
                  titulo: tr('Idioma', 'Language'),
                  subtitulo: tr('Cambia los textos y fechas al instante', 'Switches labels and dates right away'),
                  abajo: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'es', label: Text('Español')),
                        ButtonSegment(value: 'en', label: Text('English')),
                      ],
                      selected: {idiomaActual},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          _guardarPreferencia(AjustesDispositivo.idioma, s.first == 'es' ? null : s.first),
                    ),
                  ),
                ),
                _Fila(
                  icono: Icons.vibration,
                  color: const Color(0xFFD85A30),
                  titulo: tr('Vibrar al escanear', 'Vibrate on scan'),
                  derecha: Switch(
                    value: d?.vibrar ?? true,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinVibrar, v ? null : '1'),
                  ),
                ),
                _Fila(
                  icono: Icons.volume_up_outlined,
                  color: const Color(0xFF378ADD),
                  titulo: tr('Sonido al escanear', 'Sound on scan'),
                  derecha: Switch(
                    value: d?.sonar ?? true,
                    onChanged: (v) => _guardarPreferencia(AjustesDispositivo.sinSonido, v ? null : '1'),
                  ),
                ),
              ],
            ),

            // ---- Notificaciones ----
            Builder(builder: (context) {
              final (hr, mn) = d?.horaMinutoRecordatorio ?? (20, 0);
              final textoHora = '${hr.toString().padLeft(2, '0')}:${mn.toString().padLeft(2, '0')}';
              return _Seccion(
                key: _gNotificaciones,
                titulo: tr('Notificaciones (sin internet)', 'Notifications (offline)'),
                hijos: [
                  _Fila(
                    icono: Icons.schedule,
                    color: CatalogColors.naranja,
                    titulo: tr('Hora del aviso diario', 'Daily reminder time'),
                    subtitulo: tr('Revisa pendientes aunque la app esté cerrada', 'Checks pending items even when closed'),
                    alTocar: _elegirHoraRecordatorio,
                    derecha: TextButton(
                      onPressed: _elegirHoraRecordatorio,
                      child: Text(textoHora, style: mono(size: 15, weight: FontWeight.w700, color: CatalogColors.naranja)),
                    ),
                  ),
                  _Fila(
                    icono: Icons.cloud_done_outlined,
                    color: const Color(0xFF185FA5),
                    titulo: tr('Avisar al hacer respaldo', 'Notify while backing up'),
                    subtitulo: tr('Muestra cuando se está guardando y dónde quedó', 'Shows progress and destination folder'),
                    derecha: Switch(
                      value: d?.notifRespaldo ?? true,
                      onChanged: (v) async {
                        if (v) await Sistema.pedirPermisoNotificaciones();
                        await _guardarPreferencia(AjustesDispositivo.sinNotifRespaldo, v ? null : '1');
                      },
                    ),
                  ),
                  _Fila(
                    icono: Icons.print_disabled_outlined,
                    color: const Color(0xFFD85A30),
                    titulo: tr('Stickers pendientes de imprimir', 'Unprinted stickers'),
                    subtitulo: tr('Avisa si quedaron compras con 0 impresiones', 'Reminds you if purchases have 0 prints'),
                    derecha: Switch(
                      value: d?.notifSinImprimir ?? true,
                      onChanged: (v) async {
                        if (v) await Sistema.pedirPermisoNotificaciones();
                        await _guardarPreferencia(AjustesDispositivo.sinNotifSinImprimir, v ? null : '1');
                      },
                    ),
                  ),
                  _Fila(
                    icono: Icons.warning_amber_rounded,
                    color: const Color(0xFFBA7517),
                    titulo: tr('Recordatorio de respaldo externo', 'External backup reminder'),
                    subtitulo: tr('Cuando llevas varios días o compras sin enviar copia', 'When days or purchases accumulate'),
                    derecha: Switch(
                      value: d?.notifRecordarRespaldo ?? true,
                      onChanged: (v) async {
                        if (v) await Sistema.pedirPermisoNotificaciones();
                        await _guardarPreferencia(AjustesDispositivo.sinNotifRecordarRespaldo, v ? null : '1');
                      },
                    ),
                  ),
                  _Fila(
                    icono: Icons.today_outlined,
                    color: const Color(0xFF1D9E75),
                    titulo: tr('Resumen al cerrar el día', 'End-of-day summary'),
                    subtitulo: tr('Total comprado hoy si registraste compras', 'Today’s total when purchases were logged'),
                    derecha: Switch(
                      value: d?.notifResumenDia ?? true,
                      onChanged: (v) async {
                        if (v) await Sistema.pedirPermisoNotificaciones();
                        await _guardarPreferencia(AjustesDispositivo.sinNotifResumenDia, v ? null : '1');
                      },
                    ),
                  ),
                  _Fila(
                    icono: Icons.inventory_2_outlined,
                    color: const Color(0xFF7F77DD),
                    titulo: tr('Aviso de lote abierto', 'Open batch reminder'),
                    subtitulo: tr('Recuerda si dejaste un lote sin terminar', 'Reminds you if a batch was left open'),
                    derecha: Switch(
                      value: d?.notifLoteAbierto ?? true,
                      onChanged: (v) async {
                        if (v) await Sistema.pedirPermisoNotificaciones();
                        await _guardarPreferencia(AjustesDispositivo.sinNotifLoteAbierto, v ? null : '1');
                      },
                    ),
                  ),
                  _Fila(
                    icono: Icons.notifications_active_outlined,
                    color: const Color(0xFF0F8B8D),
                    titulo: tr('Probar notificación ahora', 'Send test notification'),
                    alTocar: _probarNotificacion,
                    derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                  ),
                ],
              );
            }),

            // ---- Impresora ----
            _Seccion(
              titulo: tr('Impresora de stickers', 'Sticker printer'),
              hijos: [
                _Fila(
                  key: _gImpresora,
                  icono: Icons.print_outlined,
                  color: CatalogColors.marino,
                  titulo: _impresora == null
                      ? tr('Ninguna elegida', 'None selected')
                      : (_impresora!.nombre.isNotEmpty ? _impresora!.nombre : tr('Impresora', 'Printer')),
                  subtitulo: _impresora?.descripcion ?? tr('Enciéndela y toca Buscar', 'Turn it on and tap Search'),
                  derecha: _buscando
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : TextButton(
                          onPressed: _elegirImpresora,
                          child: Text(_impresora == null ? tr('Buscar', 'Search') : tr('Cambiar', 'Change')),
                        ),
                ),
                _Fila(
                  key: _gPapel,
                  icono: Icons.straighten,
                  color: const Color(0xFF0F8B8D),
                  titulo: tr('Ancho del papel', 'Paper width'),
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
                  titulo: tr('Imprimir sticker de prueba', 'Print test sticker'),
                  alTocar: _buscando ? null : (_impresora == null ? _elegirImpresora : _imprimirPrueba),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
              ],
              nota: tr(
                'Funciona con impresoras térmicas Bluetooth clásicas, BLE y las mini impresoras de AliExpress (las de apps como iPrint o Fun Print). CataLog detecta el tipo solo. Las clásicas se emparejan primero en Ajustes de Android > Bluetooth (PIN 0000 o 1234).',
                'Works with classic Bluetooth thermal printers, BLE printers, and mini AliExpress printers (such as iPrint or Fun Print models). CataLog detects the protocol automatically. Pair classic Bluetooth printers first in Android Settings > Bluetooth (PIN 0000 or 1234).',
              ),
            ),

            // ---- Seguridad ----
            _Seccion(
              titulo: tr('Seguridad', 'Security'),
              hijos: [
                _Fila(
                  key: _gSeguridad,
                  icono: Icons.fingerprint,
                  color: const Color(0xFF3B6D11),
                  titulo: tr('Pedir huella o PIN al abrir', 'Require fingerprint or PIN on launch'),
                  subtitulo: tr('Usa el bloqueo del teléfono', 'Uses your phone screen lock'),
                  derecha: Switch(value: _bloqueo, onChanged: _cambiarBloqueo),
                ),
              ],
            ),

            // ---- Ubicar respaldo (opción roja importante de advertencia) ----
            Padding(
              padding: const EdgeInsets.only(top: 22),
              child: Container(
                key: _gUbicarRespaldo,
                decoration: BoxDecoration(
                  color: CatalogColors.rojo.withValues(alpha: CatalogColors.paleta.oscura ? 0.16 : 0.09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: CatalogColors.rojo, width: 1.8),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => ubicarRespaldosEnArchivos(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB3261E),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.folder_special, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, size: 16, color: CatalogColors.rojo),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        tr('Ubicar respaldo', 'Locate backup'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: CatalogColors.rojo,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tr(
                                    'Importante: abre tus archivos exactamente en Descargas/$carpetaRespaldos donde se guardan tus respaldos.',
                                    'Important: opens your files directly inside Downloads/$carpetaRespaldos where your backups live.',
                                  ),
                                  style: TextStyle(fontSize: 13, height: 1.35, color: CatalogColors.texto),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.open_in_new, color: CatalogColors.rojo, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ---- Respaldo y traspaso ----
            _Seccion(
              titulo: tr('Respaldo y traspaso', 'Backup & transfer'),
              hijos: [
                if (!revision) ...[
                  Consulta<DateTime?>(
                    cargar: scope.compras.ultimoRespaldo,
                    builder: (context, ultimo) => _Fila(
                      key: _gRespaldo,
                      icono: Icons.backup_outlined,
                      color: const Color(0xFF185FA5),
                      titulo: tr('Crear respaldo', 'Create backup'),
                      subtitulo: ultimo == null
                          ? tr('Todavía no has hecho ninguno', 'No backups created yet')
                          : '${tr('Último', 'Last')}: ${fechaHora(ultimo)}',
                      alTocar: () => crearRespaldoYEnviar(context),
                      derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                    ),
                  ),
                  _Fila(
                    icono: Icons.send_to_mobile_outlined,
                    color: const Color(0xFF0F6E56),
                    titulo: tr('Enviar mis compras a otro celular', 'Send my purchases to another phone'),
                    alTocar: () => enviarAOtroCelular(context),
                    derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                  ),
                ],
                _Fila(
                  icono: Icons.download_outlined,
                  color: const Color(0xFF534AB7),
                  titulo: tr('Recibir datos de otro celular', 'Receive data from another phone'),
                  alTocar: () => recibirDatos(context),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                _Fila(
                  icono: Icons.swap_horiz,
                  color: const Color(0xFF5F5E5A),
                  titulo: tr('Cambiar de sesión', 'Switch session'),
                  subtitulo: '${tr('Ahora', 'Current')}: $nombreSesion',
                  alTocar: () => mostrarSesiones(context),
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                if (!revision)
                  _Fila(
                    icono: Icons.settings_backup_restore,
                    color: const Color(0xFFA32D2D),
                    titulo: tr('Restaurar desde un respaldo', 'Restore from backup'),
                    alTocar: () => restaurarDesdeArchivo(context),
                    derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                  ),
              ],
              nota: autoRespaldo == null
                  ? tr(
                      'Copia automática diaria en $autoLugar: todavía no se ha hecho.',
                      'Daily auto backup in $autoLugar: none created yet.',
                    )
                  : tr(
                      'Copia automática diaria: la última fue el ${fechaHora(autoRespaldo)}, en $autoLugar. Envía un respaldo a tu correo o Drive de vez en cuando por si se pierde el teléfono.',
                      'Daily auto backup: last saved ${fechaHora(autoRespaldo)} in $autoLugar. Send a copy to your email or Drive periodically in case the phone is lost.',
                    ),
            ),

            // ---- Ayuda ----
            _Seccion(
              titulo: tr('Ayuda', 'Help'),
              hijos: [
                _Fila(
                  key: _gPresentacion,
                  icono: Icons.slideshow_outlined,
                  color: CatalogColors.naranja,
                  titulo: tr('Ver la presentación de nuevo', 'Replay intro walkthrough'),
                  alTocar: _verPresentacion,
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
                _Fila(
                  icono: Icons.help_outline,
                  color: const Color(0xFF378ADD),
                  titulo: tr('Volver a destacar el botón de ayuda', 'Highlight help button again'),
                  subtitulo: tr('El signo de pregunta de cada pantalla', 'The question mark icon on each screen'),
                  alTocar: _destacarAyuda,
                  derecha: Icon(Icons.chevron_right, color: CatalogColors.acero),
                ),
              ],
            ),

            const SizedBox(height: 26),
            Center(
              child: Text(
                tr('CataLog · versión $versionApp · Hecho en Arica', 'CataLog · version $versionApp · Made in Arica'),
                style: etiqueta,
              ),
            ),
            Center(
              child: Text(
                tr('Los datos se guardan solo en este teléfono.', 'All data stays strictly on this phone.'),
                style: etiqueta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grupo de ajustes: título, tarjeta con filas separadas por líneas y una nota.
class _Seccion extends StatelessWidget {
  const _Seccion({super.key, required this.titulo, required this.hijos, this.nota});

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
