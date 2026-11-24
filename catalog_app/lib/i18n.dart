/// Idioma activo de la interfaz ('es' o 'en').
///
/// Igual que la paleta de colores, lo cambia la raíz de la app cuando se elige
/// en Ajustes y enseguida reconstruye toda la pantalla sin perder dónde estabas.
class Idioma {
  static String actual = 'es';

  static bool get en => actual == 'en';
  static String get localeTag => en ? 'en' : 'es';
}

/// Texto según el idioma activo: español por defecto o inglés si se eligió 'en'.
String tr(String es, String en) => Idioma.en ? en : es;

/// Plural simple en ambos idiomas: "1 catalítico" / "3 catalíticos" o "1 converter" / "3 converters".
String contarCataliticos(int n) =>
    n == 1 ? tr('1 catalítico', '1 converter') : tr('$n catalíticos', '$n converters');
