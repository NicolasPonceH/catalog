import 'dart:io';

import '../data/base.dart';
import '../data/compras_repo.dart';
import '../data/dispositivo.dart';
import '../system/sistema.dart';
import 'respaldo.dart';

const inicioNombreAutoRespaldo = 'CataLog-auto-';

/// Un respaldo automático por día de calendario.
bool tocaRespaldoAutomatico(DateTime? ultimo, DateTime ahora) =>
    ultimo == null ||
    ultimo.year != ahora.year ||
    ultimo.month != ahora.month ||
    ultimo.day != ahora.day;

String _dos(int n) => n.toString().padLeft(2, '0');

String nombreAutoRespaldo(String prefijo, DateTime f) =>
    '$inicioNombreAutoRespaldo$prefijo-${f.year}${_dos(f.month)}${_dos(f.day)}.zip';

/// Guarda una copia diaria en Descargas/CataLog (se conservan las 3 últimas).
/// Solo para la sesión de compra. No hace nada si ya se hizo hoy o si no hay compras.
Future<void> respaldoAutomatico({
  required CatalogDb base,
  required Directory carpeta,
  required AjustesDispositivo dispositivo,
  DateTime? ahora,
}) async {
  final cuando = ahora ?? DateTime.now();
  if (!tocaRespaldoAutomatico(dispositivo.fecha(AjustesDispositivo.ultimoAutoRespaldo), cuando)) return;
  final repo = ComprasRepo(base);
  if (await repo.contarCompras() == 0) return;
  final zip = await armarRespaldo(base, carpeta, ahora: cuando);
  final lugar = await Sistema.guardarEnDescargas(
    nombreAutoRespaldo(await repo.prefijo(), cuando),
    zip,
    prefijoBorrar: inicioNombreAutoRespaldo,
    conservar: 3,
  );
  await dispositivo.guardar(AjustesDispositivo.ultimoAutoRespaldo, cuando.toIso8601String());
  if (lugar != null) await dispositivo.guardar(AjustesDispositivo.lugarAutoRespaldo, lugar);
}
