import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../features/ficha_screen.dart';
import '../theme.dart';

/// Una compra en una lista: código, precio, fecha de compra, vendedor y autos.
class CompraTile extends StatelessWidget {
  const CompraTile({super.key, required this.compra});

  final Compra compra;

  @override
  Widget build(BuildContext context) {
    final color = compra.anulada ? CatalogColors.acero : CatalogColors.marino;
    final detalle = [
      fechaHora(compra.fechaCompra),
      compra.vendedor,
      if (compra.autos.isNotEmpty) compra.autos,
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => abrir(context, FichaScreen(id: compra.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(compra.codigo, style: mono(size: 13, color: color))),
                  if (compra.anulada)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('ANULADA',
                          style: TextStyle(fontSize: 11, color: CatalogColors.rojo, fontWeight: FontWeight.w700)),
                    ),
                  Text(
                    clp(compra.precio),
                    style: mono(size: 15, color: color).copyWith(
                      decoration: compra.anulada ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(detalle, style: etiqueta, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
