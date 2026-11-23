import 'package:material_ui/material_ui.dart';

/// Colores según el tema elegido (claro u oscuro, con o sin alto contraste).
class Paleta {
  const Paleta({
    required this.fondo,
    required this.superficie,
    required this.texto,
    required this.texto2,
    required this.borde,
    required this.naranjaClara,
    required this.barra,
    required this.verde,
    required this.rojo,
    required this.oscura,
    this.grosorBorde = 1,
  });

  /// Fondo de las pantallas.
  final Color fondo;

  /// Tarjetas, campos y hojas.
  final Color superficie;

  /// Texto principal y secundario.
  final Color texto;
  final Color texto2;
  final Color borde;

  /// Fondo suave naranja de avisos.
  final Color naranjaClara;

  /// Barra de arriba y barra de pestañas.
  final Color barra;
  final Color verde;
  final Color rojo;
  final bool oscura;
  final double grosorBorde;

  static const clara = Paleta(
    fondo: Color(0xFFF4F6F8),
    superficie: Colors.white,
    texto: Color(0xFF0E2A47),
    texto2: Color(0xFF5B6B7C),
    borde: Color(0xFFDCE3EA),
    naranjaClara: Color(0xFFFFE3CF),
    barra: Color(0xFF0E2A47),
    verde: Color(0xFF2E7D4F),
    rojo: Color(0xFFB3261E),
    oscura: false,
  );

  static const oscura_ = Paleta(
    fondo: Color(0xFF0A1520),
    superficie: Color(0xFF132536),
    texto: Color(0xFFEEF2F6),
    texto2: Color(0xFF9AABBE),
    borde: Color(0xFF223A52),
    naranjaClara: Color(0xFF3B2A1C),
    barra: Color(0xFF0B1B2C),
    verde: Color(0xFF5DCAA5),
    rojo: Color(0xFFFF8A80),
    oscura: true,
  );

  static const claraContraste = Paleta(
    fondo: Colors.white,
    superficie: Colors.white,
    texto: Colors.black,
    texto2: Color(0xFF1C2733),
    borde: Color(0xFF0E2A47),
    naranjaClara: Color(0xFFFFD2B0),
    barra: Color(0xFF0E2A47),
    verde: Color(0xFF1B5E37),
    rojo: Color(0xFF8E1A13),
    oscura: false,
    grosorBorde: 2,
  );

  static const oscuraContraste = Paleta(
    fondo: Colors.black,
    superficie: Color(0xFF0A0F14),
    texto: Colors.white,
    texto2: Color(0xFFE3E9EF),
    borde: Colors.white,
    naranjaClara: Color(0xFF4A2E14),
    barra: Colors.black,
    verde: Color(0xFF7FE3BF),
    rojo: Color(0xFFFFA8A0),
    oscura: true,
    grosorBorde: 2,
  );

  static Paleta de({required bool oscuro, required bool contraste}) => switch ((oscuro, contraste)) {
        (false, false) => clara,
        (true, false) => oscura_,
        (false, true) => claraContraste,
        (true, true) => oscuraContraste,
      };
}

/// Colores de CataLog. Los de marca (marino, naranja, niebla) no cambian; los
/// demás dependen del tema activo (ver [Paleta]).
class CatalogColors {
  /// Tema activo. Lo cambia la raíz de la app y después reconstruye todo.
  static Paleta paleta = Paleta.clara;

  static const marino = Color(0xFF0E2A47);
  static const naranja = Color(0xFFFF7A1A);
  static const niebla = Color(0xFFF4F6F8);

  /// Texto principal (marino en claro, casi blanco en oscuro).
  static Color get texto => paleta.texto;

  /// Texto secundario.
  static Color get acero => paleta.texto2;
  static Color get borde => paleta.borde;
  static Color get naranjaClara => paleta.naranjaClara;
  static Color get verde => paleta.verde;
  static Color get rojo => paleta.rojo;
  static Color get fondo => paleta.fondo;
  static Color get superficie => paleta.superficie;
  static Color get barra => paleta.barra;
}

const fuenteUi = 'SpaceGrotesk';
const fuenteMono = 'IBMPlexMono';

/// Texto monoespaciado para códigos y montos.
TextStyle mono({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    TextStyle(
      fontFamily: fuenteMono,
      fontSize: size,
      fontWeight: weight,
      color: color ?? CatalogColors.texto,
    );

/// Texto secundario (etiquetas, ayudas).
TextStyle get etiqueta => TextStyle(fontSize: 13, color: CatalogColors.acero);

ThemeData catalogTheme([Paleta p = Paleta.clara]) {
  final brillo = p.oscura ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: CatalogColors.naranja, brightness: brillo).copyWith(
    primary: CatalogColors.naranja,
    onPrimary: CatalogColors.marino,
    secondary: p.oscura ? CatalogColors.naranja : CatalogColors.marino,
    onSecondary: p.oscura ? CatalogColors.marino : CatalogColors.niebla,
    surface: p.fondo,
    onSurface: p.texto,
    onSurfaceVariant: p.texto2,
    outline: p.borde,
    surfaceContainerHighest: p.superficie,
    error: p.rojo,
  );
  final radio = BorderRadius.circular(12);
  const textoBoton = TextStyle(
    fontFamily: fuenteUi,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  final borde = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: p.borde, width: p.grosorBorde),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brillo,
    colorScheme: scheme,
    fontFamily: fuenteUi,
    scaffoldBackgroundColor: p.fondo,
    canvasColor: p.fondo,
    dividerColor: p.borde,
    appBarTheme: AppBarTheme(
      backgroundColor: p.barra,
      foregroundColor: CatalogColors.niebla,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontFamily: fuenteUi,
        fontSize: 19,
        fontWeight: FontWeight.w500,
        color: CatalogColors.niebla,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CatalogColors.naranja,
        foregroundColor: CatalogColors.marino,
        minimumSize: const Size.fromHeight(52),
        textStyle: textoBoton,
        shape: RoundedRectangleBorder(borderRadius: radio),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.texto,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.oscura ? p.texto2 : CatalogColors.marino, width: 1.5),
        textStyle: textoBoton,
        shape: RoundedRectangleBorder(borderRadius: radio),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.oscura ? CatalogColors.naranja : const Color(0xFFB35300)),
    ),
    cardTheme: CardThemeData(
      color: p.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radio,
        side: BorderSide(color: p.borde, width: p.grosorBorde),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.superficie),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.superficie),
    popupMenuTheme: PopupMenuThemeData(color: p.superficie),
    listTileTheme: ListTileThemeData(iconColor: p.texto2),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.superficie,
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(
        borderSide: const BorderSide(color: CatalogColors.naranja, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: p.oscura ? CatalogColors.naranja : CatalogColors.marino,
        selectedForegroundColor: p.oscura ? CatalogColors.marino : CatalogColors.niebla,
        foregroundColor: p.texto,
        backgroundColor: p.superficie,
        side: BorderSide(color: p.borde, width: p.grosorBorde),
        textStyle: const TextStyle(fontFamily: fuenteUi, fontSize: 14),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CatalogColors.marino : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CatalogColors.naranja : null,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
