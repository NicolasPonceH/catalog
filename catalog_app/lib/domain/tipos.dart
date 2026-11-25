import '../i18n.dart';

/// Tipo de motor del auto del que sale el catalítico.
enum Motor { bencinero, diesel }

/// Material o tipo de cuerpo del catalítico.
enum TipoMaterial { ceramico, metalico, dpf }

/// Nivel de llenado o estado físico de la cerámica / monolito al comprar.
enum NivelLlenado { entero, tresCuartos, medio, fundido }

extension MotorEtiqueta on Motor {
  String get etiqueta => switch (this) {
        Motor.bencinero => tr('Bencinero', 'Gasoline'),
        Motor.diesel => tr('Diésel', 'Diesel'),
      };
}

extension TipoMaterialEtiqueta on TipoMaterial {
  String get etiqueta => switch (this) {
        TipoMaterial.ceramico => tr('Cerámico', 'Ceramic'),
        TipoMaterial.metalico => tr('Metálico', 'Metallic'),
        TipoMaterial.dpf => 'DPF',
      };
}

extension NivelLlenadoEtiqueta on NivelLlenado {
  String get claveDb => switch (this) {
        NivelLlenado.entero => 'entero',
        NivelLlenado.tresCuartos => 'tres_cuartos',
        NivelLlenado.medio => 'medio',
        NivelLlenado.fundido => 'fundido',
      };

  static NivelLlenado deClaveDb(Object? valor) => switch (valor) {
        'tres_cuartos' || 'tresCuartos' => NivelLlenado.tresCuartos,
        'medio' => NivelLlenado.medio,
        'fundido' => NivelLlenado.fundido,
        _ => NivelLlenado.entero,
      };

  String get etiqueta => switch (this) {
        NivelLlenado.entero => tr('Entero 100%', 'Full 100%'),
        NivelLlenado.tresCuartos => '3/4',
        NivelLlenado.medio => tr('Medio', 'Half'),
        NivelLlenado.fundido => tr('Fundido/Partido', 'Melted/Broken'),
      };

  String get etiquetaCorta => switch (this) {
        NivelLlenado.entero => '100%',
        NivelLlenado.tresCuartos => '3/4',
        NivelLlenado.medio => tr('Medio', 'Half'),
        NivelLlenado.fundido => tr('Fundido', 'Broken'),
      };
}

/// Texto corto del tipo, por ejemplo "Cerámico · Bencinero".
/// (Siempre se compran catalíticos originales, por eso no se indica.)
String tipoTexto(Motor motor, TipoMaterial material) => '${material.etiqueta} · ${motor.etiqueta}';
