import '../domain/periodos.dart';
import '../domain/tipos.dart';

int ms(DateTime f) => f.millisecondsSinceEpoch;
DateTime deMs(Object? v) => DateTime.fromMillisecondsSinceEpoch(v! as int);
DateTime? deMsOpcional(Object? v) =>
    v == null ? null : DateTime.fromMillisecondsSinceEpoch(v as int);

/// Lo que se escribe en el formulario de compra.
class DatosCompra {
  const DatosCompra({
    required this.fechaCompra,
    required this.vendedor,
    this.lugar = '',
    this.lat,
    this.lng,
    this.precisionM,
    required this.precio,
    required this.motor,
    required this.material,
    this.original = false,
    this.codigoFabrica = '',
    this.autos = '',
    this.fotoPath,
    this.notas = '',
  });

  final DateTime fechaCompra;
  final String vendedor;
  final String lugar;
  final double? lat;
  final double? lng;
  final double? precisionM;
  final int precio;
  final Motor motor;
  final TipoMaterial material;
  final bool original;
  final String codigoFabrica;
  final String autos;

  /// Ruta relativa dentro de la carpeta de la app, por ejemplo fotos/123.jpg.
  final String? fotoPath;
  final String notas;

  Map<String, Object?> aFila() => {
        'fecha_compra': ms(fechaCompra),
        'vendedor': vendedor.trim(),
        'lugar': lugar.trim(),
        'lat': lat,
        'lng': lng,
        'precision_m': precisionM,
        'precio': precio,
        'motor': motor.name,
        'material': material.name,
        'original': original ? 1 : 0,
        'codigo_fabrica': codigoFabrica.trim().toUpperCase(),
        'autos': autos.trim(),
        'foto_path': fotoPath,
        'notas': notas.trim(),
      };
}

/// Una compra guardada.
class Compra {
  const Compra({
    required this.id,
    required this.codigo,
    required this.fechaCompra,
    required this.vendedor,
    required this.lugar,
    this.lat,
    this.lng,
    this.precisionM,
    required this.precio,
    required this.motor,
    required this.material,
    required this.original,
    required this.codigoFabrica,
    required this.autos,
    this.fotoPath,
    required this.notas,
    required this.anulada,
    this.anuladaEn,
    required this.motivoAnulacion,
    required this.impresiones,
    required this.creadoEn,
    required this.actualizadoEn,
    this.fechaCompraEditadaEn,
  });

  factory Compra.deFila(Map<String, Object?> f) => Compra(
        id: f['id']! as int,
        codigo: f['codigo']! as String,
        fechaCompra: deMs(f['fecha_compra']),
        vendedor: f['vendedor']! as String,
        lugar: f['lugar']! as String,
        lat: (f['lat'] as num?)?.toDouble(),
        lng: (f['lng'] as num?)?.toDouble(),
        precisionM: (f['precision_m'] as num?)?.toDouble(),
        precio: f['precio']! as int,
        motor: Motor.values.byName(f['motor']! as String),
        material: TipoMaterial.values.byName(f['material']! as String),
        original: f['original'] == 1,
        codigoFabrica: f['codigo_fabrica']! as String,
        autos: f['autos']! as String,
        fotoPath: f['foto_path'] as String?,
        notas: f['notas']! as String,
        anulada: f['estado'] == 'anulada',
        anuladaEn: deMsOpcional(f['anulada_en']),
        motivoAnulacion: f['motivo_anulacion']! as String,
        impresiones: f['impresiones']! as int,
        creadoEn: deMs(f['creado_en']),
        actualizadoEn: deMs(f['actualizado_en']),
        fechaCompraEditadaEn: deMsOpcional(f['fecha_compra_editada_en']),
      );

  final int id;
  final String codigo;
  final DateTime fechaCompra;
  final String vendedor;
  final String lugar;
  final double? lat;
  final double? lng;
  final double? precisionM;
  final int precio;
  final Motor motor;
  final TipoMaterial material;
  final bool original;
  final String codigoFabrica;
  final String autos;
  final String? fotoPath;
  final String notas;
  final bool anulada;
  final DateTime? anuladaEn;
  final String motivoAnulacion;
  final int impresiones;
  final DateTime creadoEn;
  final DateTime actualizadoEn;

  /// Cuándo se corrigió la fecha de compra (null si nunca se cambió).
  final DateTime? fechaCompraEditadaEn;

  bool get tieneUbicacion => lat != null && lng != null;
  String get tipo => tipoTexto(motor, material);
}

/// Total y cantidad de compras activas en un período.
class Resumen {
  const Resumen(this.cantidad, this.total);

  static const vacio = Resumen(0, 0);

  final int cantidad;
  final int total;

  int get promedio => cantidad == 0 ? 0 : (total / cantidad).round();
}

/// Historial de precios pagados antes por un mismo código grabado de fábrica.
class ReferenciaPrecio {
  const ReferenciaPrecio({
    required this.codigoFabrica,
    required this.cantidad,
    required this.ultimoPrecio,
    required this.ultimaFecha,
    required this.promedio,
    required this.minimo,
    required this.maximo,
    this.ultimoAutos = '',
  });

  final String codigoFabrica;
  final int cantidad;
  final int ultimoPrecio;
  final DateTime ultimaFecha;
  final int promedio;
  final int minimo;
  final int maximo;
  final String ultimoAutos;
}

class FiltroHistorial {
  const FiltroHistorial({
    this.texto = '',
    this.periodo,
    this.material,
    this.soloSinImprimir = false,
  });

  final String texto;
  final Periodo? periodo;
  final TipoMaterial? material;
  final bool soloSinImprimir;
}

class DatosInvalidos implements Exception {
  DatosInvalidos(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}
