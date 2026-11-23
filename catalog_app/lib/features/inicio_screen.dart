import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../theme.dart';
import '../widgets/catalog_logo.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'ajustes_screen.dart';
import 'compra_form_screen.dart';
import 'escanear_screen.dart';
import 'historial_screen.dart';
import 'lotes_screen.dart';
import 'reportes_screen.dart';
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
  final _gEscanear = GlobalKey();
  final _gAccesos = GlobalKey();
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
    return mostrarGuia(context, [
      PasoGuia(
        clave: _gMes,
        icono: Icons.insights_outlined,
        titulo: revision ? 'Lo recibido este mes' : 'Lo gastado este mes',
        texto: 'Suma lo pagado por los catalíticos comprados este mes. Debajo ves lo de hoy.',
      ),
      PasoGuia(
        clave: _gNueva,
        icono: Icons.add_circle_outline,
        titulo: 'Registra una compra',
        texto: 'Anota vendedor, precio, tipo y foto. La fecha, la hora y el GPS se llenan solos.',
      ),
      PasoGuia(
        clave: _gEscanear,
        icono: Icons.qr_code_scanner,
        titulo: 'Escanea un sticker',
        texto: 'Apunta la cámara al QR o al código de barras del sticker y se abre la ficha del catalítico.',
      ),
      PasoGuia(
        clave: _gAccesos,
        icono: Icons.apps,
        titulo: 'Historial, lotes y reportes',
        texto: 'Busca compras pasadas, escanea muchos stickers seguidos en un lote o saca el Excel del mes.',
      ),
      PasoGuia(
        clave: _gUltimas,
        icono: Icons.receipt_long_outlined,
        titulo: 'Tus últimas compras',
        texto: 'Toca cualquiera para ver su ficha completa y reimprimir el sticker.',
      ),
      PasoGuia(
        clave: _gTraspaso,
        icono: Icons.swap_horiz,
        titulo: 'Respaldo y traspaso',
        texto: 'Crea un respaldo, manda tus compras a otro celular o cambia de sesión.',
      ),
      PasoGuia(
        clave: _gAjustes,
        icono: Icons.settings_outlined,
        titulo: 'Ajustes',
        texto: 'Tu nombre, el prefijo de los códigos, la impresora y el bloqueo con huella.',
      ),
      PasoGuia(
        clave: _gAyuda,
        icono: Icons.help_outline,
        titulo: 'Ayuda en cada pantalla',
        texto: 'Cuando tengas una duda, toca este botón: te muestra una guía como esta de la pantalla en la que estás.',
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
            tooltip: 'Respaldo y traspaso',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => mostrarRespaldoYTraspaso(context),
          ),
          IconButton(
            key: _gAjustes,
            tooltip: 'Ajustes',
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
            if (revision) _AvisoRevision(nombre: scope.sesion?.nombre ?? 'Revisión'),
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
                        texto: '$aviso Toca para respaldar.',
                        alTocar: () => crearRespaldoYEnviar(context),
                      ),
              ),
            ],
            Text(mes.nombre, style: etiqueta),
            const SizedBox(height: 6),
            Consulta<Resumen>(
              claves: [mes.desde],
              cargar: () => repo.resumen(mes),
              builder: (context, r) {
                r ??= Resumen.vacio;
                return Card(
                  key: _gMes,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(revision ? 'Compras recibidas de este mes' : 'Gastado este mes', style: etiqueta),
                        Text(clp(r.total), style: mono(size: 30)),
                        Text(
                          '${r.cantidad} ${r.cantidad == 1 ? 'catalítico' : 'catalíticos'}',
                          style: etiqueta,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Consulta<Resumen>(
              claves: [hoy.desde],
              cargar: () => repo.resumen(hoy),
              builder: (context, r) {
                r ??= Resumen.vacio;
                return Text(
                  'Hoy: ${r.cantidad} ${r.cantidad == 1 ? 'catalítico' : 'catalíticos'} por ${clp(r.total)}',
                  style: const TextStyle(fontSize: 15),
                );
              },
            ),
            const SizedBox(height: 18),
            if (!revision) ...[
              FilledButton.icon(
                key: _gNueva,
                onPressed: () => abrir(context, const CompraFormScreen()),
                icon: const Icon(Icons.add),
                label: const Text('Nueva compra'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              key: _gEscanear,
              onPressed: () => abrir(context, const EscanearScreen()),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear sticker'),
            ),
            const SizedBox(height: 10),
            Row(
              key: _gAccesos,
              children: [
                Expanded(
                  child: _BotonChico(
                    icono: Icons.history,
                    texto: 'Historial',
                    alTocar: () => abrir(context, const HistorialScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BotonChico(
                    icono: Icons.inventory_2_outlined,
                    texto: 'Lotes',
                    alTocar: () => abrir(context, const LotesScreen()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BotonChico(
                    icono: Icons.bar_chart,
                    texto: 'Reportes',
                    alTocar: () => abrir(context, const ReportesScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text('Últimas compras', style: etiqueta),
            const SizedBox(height: 8),
            Consulta<List<Compra>>(
              cargar: () => repo.ultimas(5),
              builder: (context, lista) {
                if (lista == null) return const SizedBox(height: 40);
                if (lista.isEmpty) {
                  return Card(
                    key: _gUltimas,
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Todavía no hay compras. Toca "Nueva compra" para registrar la primera.',
                        style: TextStyle(fontSize: 15, height: 1.4),
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
          ],
        ),
      ),
    );
  }
}

class _BotonChico extends StatelessWidget {
  const _BotonChico({required this.icono, required this.texto, required this.alTocar});

  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icono, color: CatalogColors.marino),
                const SizedBox(height: 4),
                Text(texto, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
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
              const Row(
                children: [
                  Icon(Icons.fact_check_outlined, color: CatalogColors.naranja),
                  SizedBox(width: 8),
                  Text('Sesión de revisión',
                      style: TextStyle(color: CatalogColors.naranja, fontWeight: FontWeight.w700, fontSize: 15)),
                ],
              ),
              const SizedBox(height: 6),
              Text(nombre, style: const TextStyle(color: CatalogColors.niebla, fontSize: 17, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text(
                'Datos recibidos de otro celular: puedes escanear y ver las fichas, pero no '
                'modificarlas. No se mezclan con tus compras.',
                style: TextStyle(color: CatalogColors.niebla, fontSize: 13, height: 1.35),
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
                label: const Text('Volver a mis compras'),
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
                  Icon(icono, color: CatalogColors.marino),
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
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.badge_outlined, color: CatalogColors.marino),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Configura el prefijo de este teléfono para que sus códigos '
                    'no se repitan con los del otro comprador.',
                    style: TextStyle(fontSize: 14, height: 1.35),
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
