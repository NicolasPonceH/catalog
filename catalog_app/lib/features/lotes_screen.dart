import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/lotes_repo.dart';
import '../domain/formato.dart';
import '../theme.dart';
import '../widgets/consulta.dart';
import 'lote_screen.dart';

/// Lista de lotes escaneados.
class LotesScreen extends StatelessWidget {
  const LotesScreen({super.key});

  Future<void> _nuevo(BuildContext context) async {
    final lote = await AppScope.of(context).lotes.crear();
    if (context.mounted) await abrir(context, LoteScreen(loteId: lote.id));
  }

  @override
  Widget build(BuildContext context) {
    final repo = AppScope.of(context).lotes;
    return Scaffold(
      appBar: AppBar(title: const Text('Lotes escaneados')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevo(context),
        backgroundColor: CatalogColors.naranja,
        foregroundColor: CatalogColors.marino,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Nuevo lote'),
      ),
      body: SafeArea(
        child: Consulta<List<LoteConTotal>>(
          cargar: repo.listar,
          builder: (context, lista) {
            if (lista == null) return const Center(child: CircularProgressIndicator());
            if (lista.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Un lote junta varios catalíticos escaneados, por ejemplo los que '
                  'entregas juntos. CataLog suma lo que pagaste por ellos y te arma el Excel.\n\n'
                  'Toca "Nuevo lote" y escanea los stickers uno tras otro.',
                  style: TextStyle(fontSize: 15, height: 1.45),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final l = lista[i];
                return Card(
                  child: ListTile(
                    onTap: () => abrir(context, LoteScreen(loteId: l.lote.id)),
                    title: Text(l.lote.nombre, style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '${l.resumen.cantidad} ${l.resumen.cantidad == 1 ? 'catalítico' : 'catalíticos'}'
                      ' · ${fechaHora(l.lote.creadoEn)}${l.lote.cerrado ? '' : ' · abierto'}',
                      style: etiqueta,
                    ),
                    trailing: Text(clp(l.resumen.total), style: mono(size: 15)),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
