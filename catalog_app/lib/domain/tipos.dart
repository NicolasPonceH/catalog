/// Tipo de motor del auto del que sale el catalítico.
enum Motor { bencinero, diesel }

/// Material o tipo de cuerpo del catalítico.
enum TipoMaterial { ceramico, metalico, dpf }

extension MotorEtiqueta on Motor {
  String get etiqueta => switch (this) {
        Motor.bencinero => 'Bencinero',
        Motor.diesel => 'Diésel',
      };
}

extension TipoMaterialEtiqueta on TipoMaterial {
  String get etiqueta => switch (this) {
        TipoMaterial.ceramico => 'Cerámico',
        TipoMaterial.metalico => 'Metálico',
        TipoMaterial.dpf => 'DPF',
      };
}

/// Texto corto del tipo, por ejemplo "Cerámico · Bencinero · Original".
String tipoTexto(Motor motor, TipoMaterial material, bool original) =>
    '${material.etiqueta} · ${motor.etiqueta}${original ? ' · Original' : ''}';
