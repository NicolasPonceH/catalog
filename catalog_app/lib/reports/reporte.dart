import '../data/compra.dart';
import '../domain/tipos.dart';

/// Un grupo del reporte (un tipo de catalítico o un vendedor).
class FilaGrupo {
  const FilaGrupo(this.nombre, this.cantidad, this.total);

  final String nombre;
  final int cantidad;
  final int total;

  int get promedio => cantidad == 0 ? 0 : (total / cantidad).round();
}

/// Reporte de compras de un período. Los totales cuentan solo compras activas.
class Reporte {
  Reporte._(this.titulo, this.compras, this.resumen, this.porTipo, this.porVendedor);

  factory Reporte.de(List<Compra> compras, {required String titulo}) {
    final activas = compras.where((c) => !c.anulada).toList();
    final total = activas.fold<int>(0, (s, c) => s + c.precio);
    return Reporte._(
      titulo,
      compras,
      Resumen(activas.length, total),
      _agrupar(activas, (c) => '${c.material.etiqueta} · ${c.motor.etiqueta}'),
      _agrupar(activas, (c) => c.vendedor.trim(), ignorarMayusculas: true),
    );
  }

  final String titulo;

  /// Todas las compras del período, incluidas las anuladas.
  final List<Compra> compras;
  final Resumen resumen;
  final List<FilaGrupo> porTipo;
  final List<FilaGrupo> porVendedor;

  int get anuladas => compras.where((c) => c.anulada).length;
}

/// Agrupa y ordena de mayor a menor total.
List<FilaGrupo> _agrupar(
  List<Compra> compras,
  String Function(Compra) clave, {
  bool ignorarMayusculas = false,
}) {
  final nombres = <String, String>{};
  final cantidad = <String, int>{};
  final total = <String, int>{};
  for (final c in compras) {
    final nombre = clave(c);
    final k = ignorarMayusculas ? nombre.toLowerCase() : nombre;
    nombres.putIfAbsent(k, () => nombre);
    cantidad[k] = (cantidad[k] ?? 0) + 1;
    total[k] = (total[k] ?? 0) + c.precio;
  }
  final filas = [for (final k in nombres.keys) FilaGrupo(nombres[k]!, cantidad[k]!, total[k]!)];
  filas.sort((a, b) => b.total != a.total ? b.total.compareTo(a.total) : a.nombre.compareTo(b.nombre));
  return filas;
}
