// Código de cada catalítico: PREFIJO-AAMMDD-NNNN.
// Código de etiqueta maestra de saco/lote: LOT-AAMMDD-NNNN o SUP-AAMMDD-NNNN.
//
// La fecha del código de compra es siempre la FECHA DE COMPRA, no la del registro.

import '../i18n.dart';

String _dos(int n) => n.toString().padLeft(2, '0');

/// Clave del día, por ejemplo 261121 para el 21/11/2026.
String diaClave(DateTime fecha) =>
    '${_dos(fecha.year % 100)}${_dos(fecha.month)}${_dos(fecha.day)}';

String normalizarPrefijo(String prefijo) => prefijo.trim().toUpperCase();

/// Prefijo que se usa si el teléfono todavía no tiene uno configurado.
const prefijoPorDefecto = 'CTL';

/// Prefijos reservados para etiquetas maestras de sacos / lotes cerrados.
const prefijosReservadosLote = {'LOT', 'SUP'};
const prefijoQrLote = 'CATALOG-LOTE|';

/// Arma el código de compra individual, por ejemplo CTL-261121-0007.
String formatearCodigo(String prefijo, DateTime fechaCompra, int numeroDelDia) =>
    '${normalizarPrefijo(prefijo)}-${diaClave(fechaCompra)}-${numeroDelDia.toString().padLeft(4, '0')}';

/// Solo letras, para que el código sin guiones se pueda leer sin ambigüedad.
/// Devuelve un mensaje de error o null si el prefijo sirve.
String? validarPrefijo(String prefijo) {
  final p = normalizarPrefijo(prefijo);
  if (!RegExp(r'^[A-Z]{2,5}$').hasMatch(p)) {
    return tr('Usa de 2 a 5 letras, sin espacios ni números', 'Use 2 to 5 letters, no spaces or numbers');
  }
  if (prefijosReservadosLote.contains(p)) {
    return tr(
      '$p está reservado para etiquetas de sacos/lotes. Elige otro prefijo (ej. CTL).',
      '$p is reserved for bag/batch labels. Choose another prefix (e.g. CTL).',
    );
  }
  return null;
}

final _conGuiones = RegExp(r'^([A-Z]{2,5})-(\d{6})-(\d{4,})$');
final _sinGuiones = RegExp(r'^([A-Z]{2,5})(\d{6})(\d{4,})$');

/// Datos extraídos al escanear el QR o código de barras de una Etiqueta Maestra de Saco / Lote.
class CodigoLoteEscaneado {
  const CodigoLoteEscaneado({
    required this.codigoLote,
    required this.loteId,
    required this.dia,
    required this.esSupervisor,
    this.nombreLote = '',
    this.totalPiezas,
    this.ceramicos,
    this.metalicos,
    this.dpf,
    this.conObservacion,
    this.responsable = '',
  });

  final String codigoLote;
  final int loteId;
  final String dia;
  final bool esSupervisor;
  final String nombreLote;
  final int? totalPiezas;
  final int? ceramicos;
  final int? metalicos;
  final int? dpf;
  final int? conObservacion;
  final String responsable;
}

/// Reconoce una Etiqueta Maestra de Saco / Lote, ya sea por su QR (`CATALOG-LOTE|...`),
/// por su código de barras (`LOT2611250001` / `SUP2611250001`) o escrita a mano (`LOT-261125-0001`).
CodigoLoteEscaneado? leerCodigoLoteEscaneado(String texto) {
  final crudo = texto.trim();
  if (crudo.toUpperCase().startsWith(prefijoQrLote)) {
    final partes = crudo.substring(prefijoQrLote.length).split('|');
    if (partes.isEmpty) return null;
    final base = _parsearCodigoLoteSimple(partes[0]);
    if (base == null) return null;
    final total = partes.length > 1 ? int.tryParse(partes[1]) : null;
    int? cer, met, dpf;
    if (partes.length > 2) {
      for (final seg in partes[2].toUpperCase().split('-')) {
        if (seg.startsWith('C')) cer = int.tryParse(seg.substring(1));
        if (seg.startsWith('M')) met = int.tryParse(seg.substring(1));
        if (seg.startsWith('D')) dpf = int.tryParse(seg.substring(1));
      }
    }
    var esSup = base.esSupervisor;
    int? conObs;
    var nombre = '';
    var resp = '';
    if (partes.length > 3) {
      if (partes[3].toUpperCase() == 'SUP') esSup = true;
      if (partes[3].toUpperCase() == 'LOT') esSup = false;
    }
    if (partes.length > 4) conObs = int.tryParse(partes[4]);
    if (partes.length > 5) nombre = partes[5].trim();
    if (partes.length > 6) resp = partes[6].trim();
    return CodigoLoteEscaneado(
      codigoLote: base.codigoLote,
      loteId: base.loteId,
      dia: base.dia,
      esSupervisor: esSup,
      nombreLote: nombre,
      totalPiezas: total,
      ceramicos: cer,
      metalicos: met,
      dpf: dpf,
      conObservacion: conObs,
      responsable: resp,
    );
  }
  return _parsearCodigoLoteSimple(crudo);
}

CodigoLoteEscaneado? _parsearCodigoLoteSimple(String texto) {
  final t = texto.trim().toUpperCase();
  final m = _conGuiones.firstMatch(t) ?? _sinGuiones.firstMatch(t);
  if (m == null) return null;
  final pref = m[1]!;
  if (!prefijosReservadosLote.contains(pref)) return null;
  final id = int.tryParse(m[3]!);
  if (id == null || id <= 0) return null;
  return CodigoLoteEscaneado(
    codigoLote: '$pref-${m[2]}-${m[3]}',
    loteId: id,
    dia: m[2]!,
    esSupervisor: pref == 'SUP',
  );
}

/// Lee un código escaneado de un catalítico individual: el QR lo trae con guiones
/// (CTL-261121-0007) y el código de barras sin guiones (CTL2611210007).
/// Si el código corresponde a un saco/lote (`LOT-...` o `SUP-...`), devuelve null
/// para que lo maneje [leerCodigoLoteEscaneado].
String? leerCodigoEscaneado(String texto) {
  if (leerCodigoLoteEscaneado(texto) != null) return null;
  final t = texto.trim().toUpperCase();
  final m = _conGuiones.firstMatch(t) ?? _sinGuiones.firstMatch(t);
  if (m == null) return null;
  return '${m[1]}-${m[2]}-${m[3]}';
}

/// Forma sin guiones para el Code128 del sticker (cabe mejor en 58 mm).
String codigoParaBarras(String codigo) => codigo.replaceAll('-', '');

/// Margen por si el reloj del teléfono está unos minutos desfasado.
const _toleranciaFutura = Duration(minutes: 5);

/// La fecha de compra es obligatoria y no puede ser futura.
/// Devuelve un mensaje de error o null si la fecha sirve.
String? validarFechaCompra(DateTime? fechaCompra, DateTime ahora) {
  if (fechaCompra == null) return tr('La fecha de compra es obligatoria', 'Purchase date is required');
  if (fechaCompra.isAfter(ahora.add(_toleranciaFutura))) {
    return tr('La fecha de compra no puede ser futura', 'Purchase date cannot be in the future');
  }
  if (fechaCompra.isBefore(DateTime(2000))) {
    return tr('Revisa la fecha de compra', 'Check the purchase date');
  }
  return null;
}

/// Deja la fecha al minuto (sin segundos), que es lo que se muestra y se guarda.
DateTime alMinuto(DateTime f) =>
    DateTime(f.year, f.month, f.day, f.hour, f.minute);
