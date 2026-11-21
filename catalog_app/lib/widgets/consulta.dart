import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../app_scope.dart';

/// Ejecuta una consulta a la base y la repite cada vez que se guarda algo,
/// o cuando cambian las [claves] (por ejemplo, un filtro).
/// Mientras carga por primera vez, [builder] recibe null.
class Consulta<T> extends StatefulWidget {
  const Consulta({
    super.key,
    required this.cargar,
    required this.builder,
    this.claves = const [],
  });

  final Future<T> Function() cargar;
  final Widget Function(BuildContext context, T? dato) builder;
  final List<Object?> claves;

  @override
  State<Consulta<T>> createState() => _ConsultaState<T>();
}

class _ConsultaState<T> extends State<Consulta<T>> {
  T? _dato;
  StreamSubscription<void>? _sub;
  int _vuelta = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub == null) {
      _sub = AppScope.of(context).base.cambios.listen((_) => _recargar());
      _recargar();
    }
  }

  @override
  void didUpdateWidget(Consulta<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.claves, widget.claves)) _recargar();
  }

  Future<void> _recargar() async {
    final vuelta = ++_vuelta;
    final dato = await widget.cargar();
    if (mounted && vuelta == _vuelta) setState(() => _dato = dato);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _dato);
}
