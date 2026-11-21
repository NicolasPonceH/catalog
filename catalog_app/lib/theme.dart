import 'package:material_ui/material_ui.dart';

/// Colores de la marca CataLog.
class CatalogColors {
  static const marino = Color(0xFF0E2A47);
  static const naranja = Color(0xFFFF7A1A);
  static const naranjaClara = Color(0xFFFFE3CF);
  static const niebla = Color(0xFFF4F6F8);
  static const acero = Color(0xFF5B6B7C);
  static const borde = Color(0xFFDCE3EA);
  static const verde = Color(0xFF2E7D4F);
  static const rojo = Color(0xFFB3261E);
}

const fuenteUi = 'SpaceGrotesk';
const fuenteMono = 'IBMPlexMono';

/// Texto monoespaciado para códigos y montos.
TextStyle mono({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color color = CatalogColors.marino,
}) =>
    TextStyle(
      fontFamily: fuenteMono,
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

/// Texto secundario (etiquetas, ayudas).
const etiqueta = TextStyle(fontSize: 13, color: CatalogColors.acero);

ThemeData catalogTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: CatalogColors.naranja).copyWith(
    primary: CatalogColors.naranja,
    onPrimary: CatalogColors.marino,
    secondary: CatalogColors.marino,
    onSecondary: CatalogColors.niebla,
    surface: CatalogColors.niebla,
    onSurface: CatalogColors.marino,
    error: CatalogColors.rojo,
  );
  final radio = BorderRadius.circular(12);
  const textoBoton = TextStyle(
    fontFamily: fuenteUi,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  final borde = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: CatalogColors.borde),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fuenteUi,
    scaffoldBackgroundColor: CatalogColors.niebla,
    appBarTheme: const AppBarTheme(
      backgroundColor: CatalogColors.marino,
      foregroundColor: CatalogColors.niebla,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
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
        foregroundColor: CatalogColors.marino,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: CatalogColors.marino, width: 1.5),
        textStyle: textoBoton,
        shape: RoundedRectangleBorder(borderRadius: radio),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radio,
        side: const BorderSide(color: CatalogColors.borde),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: borde,
      enabledBorder: borde,
      focusedBorder: borde.copyWith(
        borderSide: const BorderSide(color: CatalogColors.naranja, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: CatalogColors.marino,
        selectedForegroundColor: CatalogColors.niebla,
        foregroundColor: CatalogColors.marino,
        backgroundColor: Colors.white,
        side: const BorderSide(color: CatalogColors.borde),
        textStyle: const TextStyle(fontFamily: fuenteUi, fontSize: 14),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
