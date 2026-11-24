import '../i18n.dart';

/// Tipo de motor del auto del que sale el catalítico.
enum Motor { bencinero, diesel }

/// Material o tipo de cuerpo del catalítico.
enum TipoMaterial { ceramico, metalico, dpf }

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

/// Texto corto del tipo, por ejemplo "Cerámico · Bencinero".
/// (Siempre se compran catalíticos originales, por eso no se indica.)
String tipoTexto(Motor motor, TipoMaterial material) => '${material.etiqueta} · ${motor.etiqueta}';
