// Código de cada catalítico: PREFIJO-AAMMDD-NNNN.
//
// La fecha del código es siempre la FECHA DE COMPRA, no la del registro.

String _dos(int n) => n.toString().padLeft(2, '0');

/// Clave del día de compra, por ejemplo 261121 para el 21/11/2026.
String diaClave(DateTime fechaCompra) =>
    '${_dos(fechaCompra.year % 100)}${_dos(fechaCompra.month)}${_dos(fechaCompra.day)}';

String normalizarPrefijo(String prefijo) => prefijo.trim().toUpperCase();

/// Prefijo que se usa si el teléfono todavía no tiene uno configurado.
const prefijoPorDefecto = 'CTL';

/// Arma el código, por ejemplo CTL-261121-0007.
String formatearCodigo(String prefijo, DateTime fechaCompra, int numeroDelDia) =>
    '${normalizarPrefijo(prefijo)}-${diaClave(fechaCompra)}-${numeroDelDia.toString().padLeft(4, '0')}';

/// Solo letras, para que el código sin guiones se pueda leer sin ambigüedad.
/// Devuelve un mensaje de error o null si el prefijo sirve.
String? validarPrefijo(String prefijo) {
  final p = normalizarPrefijo(prefijo);
  if (!RegExp(r'^[A-Z]{2,5}$').hasMatch(p)) {
    return 'Usa de 2 a 5 letras, sin espacios ni números';
  }
  return null;
}

final _conGuiones = RegExp(r'^([A-Z]{2,5})-(\d{6})-(\d{4,})$');
final _sinGuiones = RegExp(r'^([A-Z]{2,5})(\d{6})(\d{4,})$');

/// Lee un código escaneado: el QR lo trae con guiones (CTL-261121-0007) y el
/// código de barras sin guiones (CTL2611210007). Devuelve siempre la forma con
/// guiones, o null si el texto no es un código CataLog.
String? leerCodigoEscaneado(String texto) {
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
  if (fechaCompra == null) return 'La fecha de compra es obligatoria';
  if (fechaCompra.isAfter(ahora.add(_toleranciaFutura))) {
    return 'La fecha de compra no puede ser futura';
  }
  if (fechaCompra.isBefore(DateTime(2000))) {
    return 'Revisa la fecha de compra';
  }
  return null;
}

/// Deja la fecha al minuto (sin segundos), que es lo que se muestra y se guarda.
DateTime alMinuto(DateTime f) =>
    DateTime(f.year, f.month, f.day, f.hour, f.minute);
