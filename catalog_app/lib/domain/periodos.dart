import 'formato.dart';

/// Rango de fechas de compra [desde, hasta).
class Periodo {
  const Periodo(this.desde, this.hasta, this.nombre);

  final DateTime desde;
  final DateTime hasta;
  final String nombre;

  bool contiene(DateTime fecha) => !fecha.isBefore(desde) && fecha.isBefore(hasta);
}

enum TipoPeriodo { todo, hoy, semana, mes }

extension TipoPeriodoEtiqueta on TipoPeriodo {
  String get etiqueta => switch (this) {
        TipoPeriodo.todo => 'Todo',
        TipoPeriodo.hoy => 'Hoy',
        TipoPeriodo.semana => 'Semana',
        TipoPeriodo.mes => 'Mes',
      };
}

Periodo periodoHoy(DateTime a) => Periodo(
      DateTime(a.year, a.month, a.day),
      DateTime(a.year, a.month, a.day + 1),
      'Hoy',
    );

/// Semana de lunes a domingo.
Periodo periodoSemana(DateTime a) {
  final lunes = DateTime(a.year, a.month, a.day - (a.weekday - DateTime.monday));
  return Periodo(lunes, DateTime(lunes.year, lunes.month, lunes.day + 7), 'Esta semana');
}

Periodo periodoMes(DateTime a) => Periodo(
      DateTime(a.year, a.month),
      DateTime(a.year, a.month + 1),
      nombreMes(a),
    );

/// Desde el primer día [desde] hasta el último día [hasta], ambos incluidos.
Periodo periodoRango(DateTime desde, DateTime hasta) => Periodo(
      DateTime(desde.year, desde.month, desde.day),
      DateTime(hasta.year, hasta.month, hasta.day + 1),
      '${fechaCorta(desde)} al ${fechaCorta(hasta)}',
    );

Periodo? periodoDe(TipoPeriodo tipo, DateTime ahora) => switch (tipo) {
      TipoPeriodo.todo => null,
      TipoPeriodo.hoy => periodoHoy(ahora),
      TipoPeriodo.semana => periodoSemana(ahora),
      TipoPeriodo.mes => periodoMes(ahora),
    };
