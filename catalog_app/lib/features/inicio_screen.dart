import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/periodos.dart';
import '../theme.dart';
import '../widgets/catalog_logo.dart';
import '../widgets/compra_tile.dart';
import '../widgets/consulta.dart';
import 'ajustes_screen.dart';
import 'compra_form_screen.dart';
import 'escanear_screen.dart';
import 'historial_screen.dart';
import 'lotes_screen.dart';
import 'reportes_screen.dart';

class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> with WidgetsBindingObserver {
  DateTime _ahora = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver a la app (por ejemplo al día siguiente) se recalculan "hoy" y "este mes".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() => _ahora = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).compras;
    final mes = periodoMes(_ahora);
    final hoy = periodoHoy(_ahora);

    return Scaffold(
      appBar: AppBar(
        title: const CatalogLogo(altura: 26, oscuro: true),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => abrir(context, const AjustesScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
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
                      alTocar: () => abrir(context, const AjustesScreen()),
                    ),
            ),
            Text(mes.nombre, style: etiqueta),
            const SizedBox(height: 6),
            Consulta<Resumen>(
              claves: [mes.desde],
              cargar: () => repo.resumen(mes),
              builder: (context, r) {
                r ??= Resumen.vacio;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gastado este mes', style: etiqueta),
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
            FilledButton.icon(
              onPressed: () => abrir(context, const CompraFormScreen()),
              icon: const Icon(Icons.add),
              label: const Text('Nueva compra'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => abrir(context, const EscanearScreen()),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Escanear sticker'),
            ),
            const SizedBox(height: 10),
            Row(
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
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Todavía no hay compras. Toca "Nueva compra" para registrar la primera.',
                        style: TextStyle(fontSize: 15, height: 1.4),
                      ),
                    ),
                  );
                }
                return Column(
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
