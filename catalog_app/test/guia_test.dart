import 'package:catalog/widgets/guia.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Pantalla de prueba con dos botones arriba y uno muy abajo en una lista.
class _Pantalla extends StatefulWidget {
  const _Pantalla();

  @override
  State<_Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<_Pantalla> {
  final a = GlobalKey();
  final b = GlobalKey();
  final abajo = GlobalKey();
  final noExiste = GlobalKey();

  Future<void> guia() => mostrarGuia(context, [
        PasoGuia(clave: a, titulo: 'Paso A', texto: 'Explica A'),
        PasoGuia(clave: noExiste, titulo: 'Paso fantasma', texto: 'No está en pantalla'),
        PasoGuia(clave: b, titulo: 'Paso B', texto: 'Explica B'),
        PasoGuia(clave: abajo, titulo: 'Paso de abajo', texto: 'Hay que bajar para verlo'),
      ]);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: [BotonAyuda(alTocar: guia)]),
        body: ListView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
          children: [
            FilledButton(key: a, onPressed: () {}, child: const Text('A')),
            const SizedBox(height: 20),
            OutlinedButton(key: b, onPressed: () {}, child: const Text('B')),
            const SizedBox(height: 4000),
            TextButton(key: abajo, onPressed: () {}, child: const Text('Abajo')),
          ],
        ),
      );
}

Future<void> _avanzar(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('la guía recorre los pasos, salta los que no existen y baja hasta los de abajo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Pantalla()));
    await tester.tap(find.byTooltip('Ayuda: guía de esta pantalla'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsOneWidget);
    expect(find.text('Explica A'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    // El paso fantasma no tiene widget: pasa directo a B.
    expect(find.text('Paso fantasma'), findsNothing);
    expect(find.text('Paso B'), findsOneWidget);

    // Atrás vuelve a A.
    await tester.tap(find.text('Atrás'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    await tester.tap(find.text('Siguiente'));
    await _avanzar(tester);
    // El último está 4000 px más abajo: la guía desplaza la lista hasta él.
    expect(find.text('Paso de abajo'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);

    await tester.tap(find.text('Listo'));
    await _avanzar(tester);
    expect(find.text('Paso de abajo'), findsNothing);
    expect(find.text('Salir de la guía'), findsNothing);
  });

  testWidgets('"Salir de la guía" la cierra en cualquier paso', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Pantalla()));
    await tester.tap(find.byTooltip('Ayuda: guía de esta pantalla'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsOneWidget);
    await tester.tap(find.text('Salir de la guía'));
    await _avanzar(tester);
    expect(find.text('Paso A'), findsNothing);
  });
}
