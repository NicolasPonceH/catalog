import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../i18n.dart';

/// Separa miles con punto: 1250000 -> "1.250.000".
String miles(int n) {
  final negativo = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${negativo ? '-' : ''}$b';
}

/// Pesos chilenos sin decimales: 180000 -> "$180.000".
String clp(int monto) => '\$${miles(monto)}';

/// Lee un monto escrito con o sin puntos. Devuelve null si está vacío.
int? parseClp(String texto) {
  final d = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  return int.parse(d.length > 12 ? d.substring(0, 12) : d);
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// 21/11/2026
String fechaCorta(DateTime f) => '${_dos(f.day)}/${_dos(f.month)}/${f.year}';

/// 10:42
String hora(DateTime f) => '${_dos(f.hour)}:${_dos(f.minute)}';

/// 21/11/2026 · 10:42
String fechaHora(DateTime f) => '${fechaCorta(f)} · ${hora(f)}';

String capitalizar(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// "viernes 21 de noviembre de 2026" / "Saturday, November 21, 2026"
String fechaLarga(DateTime f) => Idioma.en
    ? DateFormat('EEEE, MMMM d, y', 'en').format(f)
    : DateFormat("EEEE d 'de' MMMM 'de' y", 'es').format(f);

/// "Noviembre 2026" / "November 2026"
String nombreMes(DateTime f) => capitalizar(DateFormat('MMMM y', Idioma.localeTag).format(f));

/// Días de calendario entre dos fechas, sin problemas con el horario de verano.
int diasEntre(DateTime desde, DateTime hasta) =>
    DateTime.utc(hasta.year, hasta.month, hasta.day)
        .difference(DateTime.utc(desde.year, desde.month, desde.day))
        .inDays;

/// Encabezado de un día en el historial: "Hoy", "Ayer" o "Jue 20 nov 2026".
String encabezadoDia(DateTime dia, DateTime hoy) {
  final d = diasEntre(dia, hoy);
  if (d == 0) return tr('Hoy', 'Today');
  if (d == 1) return tr('Ayer', 'Yesterday');
  return capitalizar(DateFormat(Idioma.en ? 'EEE, MMM d, y' : 'EEE d MMM y', Idioma.localeTag).format(dia));
}

/// Fecha de compra para mostrar arriba del formulario: "Hoy · 10:42".
String fechaCompraCorta(DateTime f, DateTime ahora) {
  final d = diasEntre(f, ahora);
  final dia = d == 0
      ? tr('Hoy', 'Today')
      : d == 1
          ? tr('Ayer', 'Yesterday')
          : capitalizar(DateFormat(Idioma.en ? 'EEE, MMM d, y' : 'EEE d MMM y', Idioma.localeTag).format(f));
  return '$dia · ${hora(f)}';
}

/// Formatea el precio mientras se escribe: 180000 -> 180.000.
class ClpInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final monto = parseClp(newValue.text);
    if (monto == null) return const TextEditingValue();
    final texto = miles(monto);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
