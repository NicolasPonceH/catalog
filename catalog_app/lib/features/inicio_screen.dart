import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/compras_repo.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/catalog_logo.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'ajustes_screen.dart';
import 'bienvenida.dart';
import 'compra_form_screen.dart';
import 'historial_screen.dart';
import 'lote_screen.dart';
import 'principal_screen.dart';
import 'traspaso.dart';

/// Al subir su valor, el Inicio muestra su guía (la pide la presentación de la primera vez).
final pedirGuiaInicio = ValueNotifier<int>(0);

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> with WidgetsBindingObserver {
  DateTime _ahora = DateTime.now();

  // Partes que ilumina la guía.
  final _gMes = GlobalKey();
  final _gNueva = GlobalKey();
  final _gHoy = GlobalKey();
  final _gUltimas = GlobalKey();
  final _gTraspaso = GlobalKey();
  final _gAjustes = GlobalKey();
  final _gAyuda = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pedirGuiaInicio.addListener(_guiaPedida);
  }

  @override
  void dispose() {
    pedirGuiaInicio.removeListener(_guiaPedida);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _guiaPedida() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mostrarGuia();
    });
  }

  Future<void> _mostrarGuia() {
    final revision = AppScope.of(context).soloLectura;
    final barra = BarraPrincipal.of(context);
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gMes,
        icono: Icons.insights_outlined,
        titulo: revision
            ? tr('Lo recibido este mes', 'Received this month')
            : tr('Lo gastado este mes', 'Spent this month'),
        texto: tr(
          'Suma lo pagado por los catalíticos comprados este mes, con el promedio por pieza. Las barras son los últimos meses (el naranjo es este) y abajo ves cuánto cambió respecto al mes pasado.',
          'Adds up what you paid for converters bought this month, with the average per unit. The bars show recent months (orange is this month) and below you see the change vs. last month.',
        ),
      ),
      PasoGuia(
        clave: _gHoy,
        icono: Icons.today_outlined,
        titulo: tr('Hoy y lotes', 'Today & batches'),
        texto: tr(
          'Lo comprado hoy y el lote que tengas abierto. Tócalos para ir al historial o a los lotes.',
          'What you bought today and your currently open batch. Tap them to jump to history or batches.',
        ),
      ),
      PasoGuia(
        clave: _gNueva,
        icono: Icons.add_circle_outline,
        titulo: tr('Registra una compra', 'Record a purchase'),
        texto: tr(
          'Anota vendedor, precio, tipo y foto. La fecha, la hora y el GPS se llenan solos.',
          'Enter seller, price, type, and photo. Date, time, and GPS fill in automatically.',
        ),
      ),
      if (barra != null) ...[
        PasoGuia(
          clave: barra.claveEscanear,
          icono: Icons.qr_code_scanner,
          titulo: tr('Escanea un sticker', 'Scan a sticker'),
          texto: tr(
            'El botón naranja de abajo abre la cámara: apunta al QR o al código de barras y se abre la ficha.',
            'The orange button below opens the camera: point at the QR code or barcode to open its record.',
          ),
        ),
        PasoGuia(
          clave: barra.claveBarra,
          icono: Icons.apps,
          titulo: tr('Historial, lotes y reportes', 'History, batches & reports'),
          texto: tr(
            'Cambia de pestaña aquí abajo: busca compras pasadas, escanea muchos stickers en un lote o saca el Excel del mes.',
            'Switch tabs down here: search past purchases, scan multiple stickers in a batch, or export the monthly Excel.',
          ),
        ),
      ],
      PasoGuia(
        clave: _gUltimas,
        icono: Icons.receipt_long_outlined,
        titulo: tr('Tus últimas compras', 'Your recent purchases'),
        texto: tr(
          'Toca cualquiera para ver su ficha completa y reimprimir el sticker.',
          'Tap any item to view its full record and reprint the sticker.',
        ),
      ),
      PasoGuia(
        clave: _gTraspaso,
        icono: Icons.swap_horiz,
        titulo: tr('Respaldo y traspaso', 'Backup & transfer'),
        texto: tr(
          'Crea un respaldo, manda tus compras a otro celular o cambia de sesión.',
          'Create a backup, send your purchases to another phone, or switch sessions.',
        ),
      ),
      PasoGuia(
        clave: _gAjustes,
        icono: Icons.settings_outlined,
        titulo: tr('Ajustes', 'Settings'),
        texto: tr(
          'Tu nombre, el prefijo de los códigos, el idioma, el tema, la impresora y el bloqueo con huella.',
          'Your name, code prefix, language, theme, printer, and fingerprint lock.',
        ),
      ),
      PasoGuia(
        clave: _gAyuda,
        icono: Icons.help_outline,
        titulo: tr('Ayuda en cada pantalla', 'Help on every screen'),
        texto: tr(
          'Cuando tengas una duda, toca este botón: te muestra una guía como esta de la pantalla en la que estás.',
          'Whenever you have a question, tap this button: it shows a step-by-step guide for the current screen.',
        ),
      ),
    ]);
  }

  // Al volver a la app (por ejemplo al día siguiente) se recalculan "hoy" y "este mes".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() => _ahora = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final repo = scope.compras;
    final revision = scope.soloLectura;
    final mes = periodoMes(_ahora);
    final hoy = periodoHoy(_ahora);

    return Scaffold(
      appBar: AppBar(
        // En teléfonos chicos con letra grande el logo se achica para dejar sitio a los botones.
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CatalogLogo(altura: 26, oscuro: true),
        ),
        actions: [
          BotonAyuda(key: _gAyuda, alTocar: _mostrarGuia),
          IconButton(
            key: _gTraspaso,
            tooltip: tr('Respaldo y traspaso', 'Backup & transfer'),
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => mostrarRespaldoYTraspaso(context),
          ),
          IconButton(
            key: _gAjustes,
            tooltip: tr('Ajustes', 'Settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => abrir(context, const AjustesScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(4000), // construye todo el Inicio, para la guía
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (revision) _AvisoRevision(nombre: scope.sesion?.nombre ?? tr('Revisión', 'Review')),
            if (!revision) ...[
              Consulta<bool>(
                cargar: () async => (await repo.leerAjuste('prefijo')) != null,
                builder: (context, configurado) =>
                    configurado == false ? const _AvisoPrefijo() : const SizedBox.shrink(),
              ),
              Consulta<String?>(
                claves: [_ahora],
                cargar: repo.avisoRespaldo,
                builder: (context, aviso) => aviso == null
                    ? const SizedBox.shrink()
                    : _Aviso(
                        icono: Icons.backup_outlined,
                        texto: '$aviso ${tr('Toca para respaldar.', 'Tap to back up.')}',
                        alTocar: () => crearRespaldoYEnviar(context),
                      ),
              ),
              Consulta<int>(
                claves: [_ahora],
                cargar: repo.contarSinImprimir,
                builder: (context, sinSticker) {
                  if (sinSticker == null || sinSticker <= 0) return const SizedBox.shrink();
                  return _AvisoBordeado(
                    icono: Icons.print_disabled_outlined,
                    titulo: sinSticker == 1
                        ? tr('1 catalítico sin sticker impreso', '1 converter without printed sticker')
                        : tr('$sinSticker catalíticos sin sticker impreso', '$sinSticker converters without printed sticker'),
                    subtitulo: tr(
                      'Toca aquí para verlos e imprimir sus stickers pendientes.',
                      'Tap here to view them and print their pending stickers.',
                    ),
                    alTocar: () {
                      pedirFiltroSinImprimir.value++;
                      BarraPrincipal.of(context)?.irA(Pestana.historial);
                    },
                  );
                },
              ),
              Consulta<List<LoteConTotal>>(
                claves: [_ahora],
                cargar: scope.lotes.listar,
                builder: (context, lotes) {
                  final abiertos = lotes?.where((l) => !l.lote.cerrado).toList() ?? const [];
                  if (abiertos.isEmpty) return const SizedBox.shrink();
                  final primero = abiertos.first;
                  return _AvisoBordeado(
                    icono: Icons.inventory_2,
                    titulo: abiertos.length == 1
                        ? tr('Lote abierto: "${primero.lote.nombre}"', 'Open batch: "${primero.lote.nombre}"')
                        : tr('${abiertos.length} lotes abiertos sin cerrar', '${abiertos.length} open batches not closed'),
                    subtitulo: tr(
                      '${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)} · Toca para seguir escaneando o cerrarlo.',
                      '${contarCataliticos(primero.resumen.cantidad)} · ${clp(primero.resumen.total)} · Tap to keep scanning or close it.',
                    ),
                    alTocar: () => abrir(context, LoteScreen(loteId: primero.lote.id)),
                  );
                },
              ),
            ],
            // Saludo por la hora y el nombre.
            Consulta<String?>(
              claves: [_ahora.hour],
              cargar: () => repo.leerAjuste('nombre'),
              builder: (context, nombre) {
                final corto = (nombre ?? '').trim().split(RegExp(r'\s+')).first;
                return Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Text(
                    corto.isEmpty ? saludoPorHora(_ahora) : '${saludoPorHora(_ahora)}, $corto',
                    style: TextStyle(fontSize: 15, color: CatalogColors.acero),
                  ),
                );
              },
            ),
            Consulta<List<Resumen>>(
              key: _gMes,
              claves: [mes.desde],
              cargar: () => _ultimosMeses(repo, 6),
              builder: (context, meses) => _TarjetaMes(
                meses: meses,
                ahora: _ahora,
                revision: revision,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              key: _gHoy,
              children: [
                Expanded(
                  child: Consulta<Resumen>(
                    claves: [hoy.desde],
                    cargar: () => repo.resumen(hoy),
                    builder: (context, r) {
                      r ??= Resumen.vacio;
                      return _TarjetaChica(
                        icono: Icons.today_outlined,
                        titulo: tr('Hoy', 'Today'),
                        valor: clp(r.total),
                        detalle: contarCataliticos(r.cantidad),
                        alTocar: () => BarraPrincipal.of(context)?.irA(Pestana.historial),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Consulta<List<LoteConTotal>>(
                    cargar: scope.lotes.listar,
                    builder: (context, lotes) {
                      final abierto = lotes?.where((l) => !l.lote.cerrado).firstOrNull;
                      return _TarjetaChica(
                        icono: abierto == null ? Icons.inventory_2_outlined : Icons.warning_amber_rounded,
                        titulo: abierto == null ? tr('Lotes', 'Batches') : tr('Lote abierto', 'Open batch'),
                        valor: abierto == null ? '${lotes?.length ?? 0}' : clp(abierto.resumen.total),
                        detalle: abierto == null
                            ? tr('Ninguno abierto', 'None open')
                            : '${abierto.lote.nombre} · ${tr('sin cerrar', 'open')}',
                        destacada: abierto != null,
                        alTocar: () => abierto != null
                            ? abrir(context, LoteScreen(loteId: abierto.lote.id))
                            : BarraPrincipal.of(context)?.irA(Pestana.lotes),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!revision)
              FilledButton.icon(
                key: _gNueva,
                onPressed: () => abrir(context, const CompraFormScreen()),
                icon: const Icon(Icons.add),
                label: Text(tr('Nueva compra', 'New purchase')),
              ),
            // Escanear, Historial, Lotes y Reportes están en la barra de abajo.
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(tr('Últimas compras', 'Recent purchases'), style: etiqueta.copyWith(fontWeight: FontWeight.w500)),
            ),
            const SizedBox(height: 8),
            Consulta<List<Compra>>(
              cargar: () => repo.ultimas(5),
              builder: (context, lista) {
                if (lista == null) return const SizedBox(height: 40);
                if (lista.isEmpty) {
                  return Card(
                    key: _gUltimas,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        tr(
                          'Todavía no hay compras. Toca "Nueva compra" para registrar la primera.',
                          'No purchases yet. Tap "New purchase" to record your first one.',
                        ),
                        style: const TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ),
                  );
                }
                return Column(
                  key: _gUltimas,
                  children: [
                    for (final c in lista)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CompraTile(compra: c),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}


/// Totales de los últimos [n] meses por fecha de compra, del más viejo al actual.
Future<List<Resumen>> _ultimosMeses(ComprasRepo repo, int n) async {
  final ahora = DateTime.now();
  return [
    for (var k = n - 1; k >= 0; k--) await repo.resumen(periodoMes(DateTime(ahora.year, ahora.month - k))),
  ];
}

/// Tarjeta azul del mes: total en grande, cantidad y promedio, barras de los
/// últimos meses y la comparación con el mes anterior.
class _TarjetaMes extends StatelessWidget {
  const _TarjetaMes({required this.meses, required this.ahora, required this.revision});

  final List<Resumen>? meses;
  final DateTime ahora;
  final bool revision;

  @override
  Widget build(BuildContext context) {
    final lista = meses ?? const <Resumen>[];
    final r = lista.isEmpty ? Resumen.vacio : lista.last;
    final anterior = lista.length >= 2 ? lista[lista.length - 2] : null;
    final maximo = lista.fold<int>(1, (m, x) => x.total > m ? x.total : m);
    final nombreMes = DateFormat('MMMM', Idioma.localeTag).format(ahora);
    final nombreAnterior = DateFormat('MMMM', Idioma.localeTag).format(DateTime(ahora.year, ahora.month - 1));
    String? comparacion;
    if (anterior != null && anterior.total > 0) {
      final pct = ((r.total - anterior.total) / anterior.total * 100).round();
      comparacion = pct == 0
          ? tr('Igual que $nombreAnterior', 'Same as $nombreAnterior')
          : tr('${pct > 0 ? '+' : ''}$pct% que $nombreAnterior', '${pct > 0 ? '+' : ''}$pct% vs $nombreAnterior');
    }
    const tenue = Color(0xB3FFFFFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: CatalogColors.marino,
        borderRadius: BorderRadius.circular(18),
        border: CatalogColors.paleta.oscura || CatalogColors.paleta.grosorBorde > 1
            ? Border.all(color: CatalogColors.borde, width: CatalogColors.paleta.grosorBorde)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  revision ? tr('Recibido en $nombreMes', 'Received in $nombreMes') : tr('Gastado en $nombreMes', 'Spent in $nombreMes'),
                  style: const TextStyle(color: tenue, fontSize: 13),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(clp(r.total), style: mono(size: 30, color: CatalogColors.naranja)),
                ),
                Text(
                  '${contarCataliticos(r.cantidad)}'
                  '${r.cantidad > 0 ? ' · ${tr('promedio', 'avg')} ${clp(r.promedio)}' : ''}',
                  style: const TextStyle(color: tenue, fontSize: 12.5),
                ),
                if (comparacion != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0x335DCAA5),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(comparacion, style: const TextStyle(color: Color(0xFF9FE1CB), fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Barras de los últimos meses; la del mes actual en naranja.
          SizedBox(
            height: 58,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < lista.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      width: 8,
                      height: 6 + 52 * (lista[i].total / maximo),
                      decoration: BoxDecoration(
                        color: i == lista.length - 1 ? CatalogColors.naranja : const Color(0x40FFFFFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta chica (hoy, lote abierto) que lleva a su pestaña.
class _TarjetaChica extends StatelessWidget {
  const _TarjetaChica({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.detalle,
    required this.alTocar,
    this.destacada = false,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final String detalle;
  final VoidCallback alTocar;
  final bool destacada;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: destacada
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: CatalogColors.naranja, width: 1.8),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: alTocar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icono, size: 16, color: CatalogColors.naranja),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      titulo,
                      style: destacada
                          ? etiqueta.copyWith(color: CatalogColors.naranja, fontWeight: FontWeight.w700)
                          : etiqueta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor, style: mono(size: 17)),
              ),
              Text(detalle, style: etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta con borde naranja marcado para avisar stickers sin imprimir o lotes abiertos.
class _AvisoBordeado extends StatelessWidget {
  const _AvisoBordeado({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.alTocar,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: CatalogColors.naranja.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: const BorderSide(color: CatalogColors.naranja, width: 1.8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: CatalogColors.naranja,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icono, color: CatalogColors.marino, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitulo,
                        style: etiqueta.copyWith(fontSize: 12.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: CatalogColors.naranja),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Avisa que se están viendo datos de otro celular, sin poder modificarlos.
class _AvisoRevision extends StatelessWidget {
  const _AvisoRevision({required this.nombre});

  final String nombre;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: CatalogColors.marino,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_outlined, color: CatalogColors.naranja),
                  const SizedBox(width: 8),
                  Text(
                    tr('Sesión de revisión', 'Review session'),
                    style: const TextStyle(color: CatalogColors.naranja, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(nombre, style: const TextStyle(color: CatalogColors.niebla, fontSize: 17, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                tr(
                  'Datos recibidos de otro celular: puedes escanear y ver las fichas, pero no modificarlas. No se mezclan con tus compras.',
                  'Data received from another phone: you can scan and inspect records, without modifying them or mixing them with your own purchases.',
                ),
                style: const TextStyle(color: CatalogColors.niebla, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: CatalogColors.niebla,
                  side: const BorderSide(color: CatalogColors.niebla),
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () {
                  final principal = scope.sesiones?.principal;
                  if (principal != null) scope.acciones?.abrirSesion(principal);
                },
                icon: const Icon(Icons.shopping_bag_outlined),
                label: Text(tr('Volver a mis compras', 'Back to my purchases')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, required this.alTocar});

  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          color: CatalogColors.naranjaClara,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: alTocar,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icono, color: CatalogColors.texto),
                  const SizedBox(width: 12),
                  Expanded(child: Text(texto, style: const TextStyle(fontSize: 14, height: 1.35))),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );
}

class _AvisoPrefijo extends StatelessWidget {
  const _AvisoPrefijo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: CatalogColors.naranjaClara,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => abrir(context, const AjustesScreen()),
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: CatalogColors.texto),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr(
                      'Configura el prefijo de este teléfono para que sus códigos no se repitan con los del otro comprador.',
                      'Set up this phone’s prefix so its codes never collide with another buyer’s.',
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.35),
                  ),
                ),
                Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
