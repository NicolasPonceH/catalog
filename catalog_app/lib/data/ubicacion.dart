import 'package:geolocator/geolocator.dart';

/// Resultado de leer el GPS. El GPS funciona sin internet.
class LecturaGps {
  const LecturaGps.ok(double this.lat, double this.lng, this.precisionM) : error = null;
  const LecturaGps.error(String this.error)
      : lat = null,
        lng = null,
        precisionM = null;

  final double? lat;
  final double? lng;
  final double? precisionM;
  final String? error;

  bool get ok => lat != null;
}

Future<LecturaGps> leerUbicacion() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LecturaGps.error('El GPS del teléfono está apagado');
    }
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }
    if (permiso == LocationPermission.denied ||
        permiso == LocationPermission.deniedForever) {
      return const LecturaGps.error('CataLog no tiene permiso de ubicación');
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      return LecturaGps.ok(pos.latitude, pos.longitude, pos.accuracy);
    } catch (_) {
      // Sin señal clara: se usa la última posición conocida, si hay.
      final ultima = await Geolocator.getLastKnownPosition();
      if (ultima != null) {
        return LecturaGps.ok(ultima.latitude, ultima.longitude, ultima.accuracy);
      }
      return const LecturaGps.error('No se pudo obtener la ubicación');
    }
  } catch (e) {
    return LecturaGps.error('Error del GPS: $e');
  }
}
