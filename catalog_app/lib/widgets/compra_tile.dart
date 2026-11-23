import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';
import '../data/compra.dart';
import '../domain/formato.dart';
import '../domain/tipos.dart';
import '../features/ficha_screen.dart';
import '../theme.dart';

/// Cuadrito de color con la inicial del material: C cerámico, M metálico, D DPF.
class MarcaTipo extends StatelessWidget {
  const MarcaTipo({super.key, required this.material, this.anulada = false, this.tamano = 36});

  final TipoMaterial material;
  final bool anulada;
  final double tamano;

  static Color colorDe(TipoMaterial m) => switch (m) {
        TipoMaterial.ceramico => const Color(0xFF1D9E75),
        TipoMaterial.metalico => const Color(0xFF5F7A8A),
        TipoMaterial.dpf => const Color(0xFF7F77DD),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: tamano,
      height: tamano,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: anulada ? CatalogColors.acero.withValues(alpha: 0.35) : colorDe(material),
        borderRadius: BorderRadius.circular(tamano * 0.28),
      ),
      child: Text(
        material == TipoMaterial.dpf ? 'D' : material.etiqueta.characters.first,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: tamano * 0.42),
      ),
    );
  }
}

/// Una compra en una lista: código, precio, fecha de compra, vendedor y autos.
class CompraTile extends StatelessWidget {
  const CompraTile({super.key, required this.compra});

  final Compra compra;

  @override
  Widget build(BuildContext context) {
    final color = compra.anulada ? CatalogColors.acero : CatalogColors.texto;
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
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          child: Row(
            children: [
              MarcaTipo(material: compra.material, anulada: compra.anulada),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(compra.codigo, style: mono(size: 13, color: color))),
                        if (compra.anulada)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}
