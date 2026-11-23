import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../data/compras_repo.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../theme.dart';
import '../widgets/catalog_logo.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import '../widgets/guia.dart';
import 'ajustes_screen.dart';
import 'bienvenida.dart';
import 'compra_form_screen.dart';
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
        titulo: revision ? 'Lo recibido este mes' : 'Lo gastado este mes',
        texto: 'Suma lo pagado por los catalíticos comprados este mes, con el promedio por pieza. Las barras '
            'son los últimos meses (el naranjo es este) y abajo ves cuánto cambió respecto al mes pasado.',
      ),
      PasoGuia(
        clave: _gHoy,
        icono: Icons.today_outlined,
        titulo: 'Hoy y lotes',
        texto: 'Lo comprado hoy y el lote que tengas abierto. Tócalos para ir al historial o a los lotes.',
      ),
      PasoGuia(
        clave: _gNueva,
        icono: Icons.add_circle_outline,
        titulo: 'Registra una compra',
        texto: 'Anota vendedor, precio, tipo y foto. La fecha, la hora y el GPS se llenan solos.',
      ),
      if (barra != null) ...[
        PasoGuia(
          clave: barra.claveEscanear,
          icono: Icons.qr_code_scanner,
          titulo: 'Escanea un sticker',
          texto: 'El botón naranja de abajo abre la cámara: apunta al QR o al código de barras y se abre la ficha.',
        ),
        PasoGuia(
          clave: barra.claveBarra,
          icono: Icons.apps,
          titulo: 'Historial, lotes y reportes',
          texto: 'Cambia de pestaña aquí abajo: busca compras pasadas, escanea muchos stickers en un lote o '
              'saca el Excel del mes.',
        ),
      ],
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
                        titulo: 'Hoy',
                        valor: clp(r.total),
                        detalle: '${r.cantidad} ${r.cantidad == 1 ? 'catalítico' : 'catalíticos'}',
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
                        icono: Icons.inventory_2_outlined,
                        titulo: abierto == null ? 'Lotes' : 'Lote abierto',
                        valor: abierto == null ? '${lotes?.length ?? 0}' : clp(abierto.resumen.total),
                        detalle: abierto?.lote.nombre ?? 'Ninguno abierto',
                        alTocar: () => BarraPrincipal.of(context)?.irA(Pestana.lotes),
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
                label: const Text('Nueva compra'),
              ),
            // Escanear, Historial, Lotes y Reportes están en la barra de abajo.
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text('Últimas compras', style: etiqueta.copyWith(fontWeight: FontWeight.w500)),
            ),
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
    final nombreMes = DateFormat('MMMM', 'es').format(ahora);
    final nombreAnterior = DateFormat('MMMM', 'es').format(DateTime(ahora.year, ahora.month - 1));
    String? comparacion;
    if (anterior != null && anterior.total > 0) {
      final pct = ((r.total - anterior.total) / anterior.total * 100).round();
      comparacion = pct == 0
          ? 'Igual que $nombreAnterior'
          : '${pct > 0 ? '+' : ''}$pct% que $nombreAnterior';
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
                  revision ? 'Recibido en $nombreMes' : 'Gastado en $nombreMes',
                  style: const TextStyle(color: tenue, fontSize: 13),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(clp(r.total), style: mono(size: 30, color: CatalogColors.naranja)),
                ),
                Text(
                  '${r.cantidad} ${r.cantidad == 1 ? 'catalítico' : 'catalíticos'}'
                  '${r.cantidad > 0 ? ' · promedio ${clp(r.promedio)}' : ''}',
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
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final String detalle;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  Expanded(child: Text(titulo, style: etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis)),
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
