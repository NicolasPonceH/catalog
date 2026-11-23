import 'dart:io';

import 'package:catalog/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la versión que muestra la app es la de pubspec.yaml', () {
    final linea = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = linea.split(':')[1].trim().split('+').first;
    expect(versionApp, version);
  });
}
