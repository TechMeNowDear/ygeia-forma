// Round 10, g4 (αποθήκευση, CI): R10-B6-2 = R10-B7-1 — τα κατώτατα του CI από το #108 και, όπως στο Kotlin, ο έλεγχος
// «όχι λιγότερες δοκιμές Dart από όσες δηλώνουν τα αρχεία». Η πύλη του workflow ΤΡΕΧΕΙ εδώ με bash, με ψεύτικο tests.log
// και ψεύτικα αρχεία δοκιμών (όχι απλός έλεγχος κειμένου). Το R10-B6-1 (ανάγνωση χαλασμένης βάσης) ελέγχεται στο
// R10G4Test.kt (Kotlin). Όλα τα δεδομένα είναι επινοημένα.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _workflows = ['.github/workflows/check.yml', '.github/workflows/android.yml'];

/// Το κομμάτι του βήματος «Έλεγχοι» του [workflow] που μετρά τις δοκιμές Dart: από το «n=$(grep … tests passed» ως το
/// «fi» του ελέγχου «όσες δηλώνονται».
String _gate(String workflow) {
  final y = File(workflow).readAsStringSync();
  final a = y.indexOf(r"n=$(grep -aoE '[0-9]+ tests passed' tests.log");
  expect(a, greaterThanOrEqualTo(0), reason: workflow);
  const declared = r'if [ "${n:-0}" -lt "${want:-0}" ]; then';
  final b = y.indexOf(declared, a);
  expect(b, greaterThan(a), reason: '$workflow: ο έλεγχος «όσες δηλώνονται» στο βήμα των δοκιμών Dart');
  final e = y.indexOf('fi', b + declared.length);
  expect(e, greaterThan(b), reason: workflow);
  return y.substring(a, e + 2);
}

/// Τρέχει την πύλη [gate] με bash (όπως το GitHub Actions: «bash -e» και «set -o pipefail») στον [dir], με [log] ως
/// tests.log και ένα αρχείο «fN_test.dart» για κάθε στοιχείο του [files] (η λίστα «$files» του βήματος).
({int code, String out}) _run(String gate, Directory dir, String log, List<String> files) {
  final names = <String>[];
  for (var i = 0; i < files.length; i++) {
    final name = 'f${i}_test.dart';
    File('${dir.path}/$name').writeAsStringSync(files[i]);
    names.add(name);
  }
  File('${dir.path}/tests.log').writeAsStringSync(log);
  final list = names.join(' ');
  final script = 'set -o pipefail\nfiles="$list"\n$gate\n';
  final r = Process.runSync('bash', ['-e', '-c', script],
      workingDirectory: dir.path, stdoutEncoding: utf8, stderrEncoding: utf8);
  for (final n in names) {
    File('${dir.path}/$n').deleteSync();
  }
  return (code: r.exitCode, out: '${r.stdout}');
}

void main() {
  for (final wf in _workflows) {
    group('R10-B6-2 = R10-B7-1: πύλη δοκιμών Dart ($wf)', () {
      late Directory dir;
      setUp(() => dir = Directory.systemTemp.createTempSync('r10g4'));
      tearDown(() => dir.deleteSync(recursive: true));

      test('κατώτατο από το #108 (≈ 3% κάτω από τις 2.155 που έτρεξαν): ένα λιγότερο → κόκκινο', () {
        final gate = _gate(wf);
        final floor = int.parse(RegExp(r'if \[ "\$\{n:-0\}" -lt (\d+) \]; then').firstMatch(gate)!.group(1)!);
        // Πριν 1.937 (από το #107): μπορούσαν να χαθούν όλες οι δοκιμές του γύρου 9 χωρίς να το δει κανείς.
        expect(floor, greaterThanOrEqualTo(2090));
        const one = ["test('a', () {});\n"];
        final low = _run(gate, dir, '${floor - 1} tests passed.\n', one);
        expect(low.code, isNot(0));
        expect(low.out, contains('κατώτατο $floor'));
        expect(_run(gate, dir, '🎉 $floor tests passed.\n', one).code, 0);
        // Η μορφή της Flutter εκτός GitHub («+N: All tests passed!»).
        expect(_run(gate, dir, '00:40 +$floor: All tests passed!\n', one).code, 0);
        // Καμία σύνοψη στο log: κόκκινο.
        expect(_run(gate, dir, '', one).code, isNot(0));
      });

      test('λιγότερες από όσες δηλώνουν τα αρχεία (skip, ομάδα που δεν έτρεξε) → κόκκινο, και πάνω από το κατώτατο', () {
        final gate = _gate(wf);
        // 2.500 δηλωμένες: «test(» και «testWidgets(» στην αρχή της γραμμής (και με εσοχή)· όχι σχόλιο, group, testX ή
        // «test» μέσα σε έκφραση.
        final body = StringBuffer('void main() {\n');
        for (var i = 0; i < 2498; i++) {
          body.writeln("  test('t$i', () {});");
        }
        body
          ..writeln("testWidgets('w', (t) async {});")
          ..writeln("test('x', () {});")
          ..writeln("  // test('σχόλιο', () {});")
          ..writeln("  group('ομάδα', () {});")
          ..writeln("  testX('όχι');")
          ..writeln('  expect(test, isNotNull);')
          ..writeln('}');
        final files = [body.toString()];
        final same = _run(gate, dir, '2500 tests passed.\n', files);
        expect(same.code, 0, reason: same.out);
        expect(same.out, contains('στον κώδικα: 2500'));
        final less = _run(gate, dir, '2499 tests passed, 1 skipped.\n', files);
        expect(less.code, isNot(0));
        expect(less.out, contains('δηλώνουν 2500'));
        // Μετρούν όλα τα αρχεία της λίστας του «flutter test».
        final two = [...files, "  testWidgets('z', (t) async {});\n"];
        expect(_run(gate, dir, '2500 tests passed.\n', two).code, isNot(0));
        expect(_run(gate, dir, '2501 tests passed.\n', two).code, 0);
        // Ένας βρόχος δίνει περισσότερες από όσες δηλώνονται: πράσινο.
        expect(_run(gate, dir, '2600 tests passed.\n', files).code, 0);
      });

      test('Kotlin: κατώτατα από το #108 (117 κινητό, 197 ρολόι), μαζί με το «όχι λιγότεροι από τα @Test»', () {
        // Εδώ μόνο οι αριθμοί (η πύλη Kotlin διαβάζει τα XML του Gradle, που δεν υπάρχουν σε αυτή τη δοκιμή· η λογική της
        // δεν άλλαξε). Πριν 96 / 180: μπορούσαν να χαθούν όλες οι κλάσεις R9 χωρίς να το δει κανείς.
        final y = File(wf).readAsStringSync();
        final floors = [
          for (final m in RegExp(r'if \[ "\$\{n:-0\}" -lt (\d+) \] \|\| \[ \$\(\( \$\{n:-0\} \+ 2 \)\) -lt "\$\{want:-0\}" \]; then')
              .allMatches(y))
            int.parse(m.group(1)!),
        ];
        expect(floors.length, 2);
        expect(floors[0], greaterThanOrEqualTo(113), reason: 'κινητό');
        expect(floors[1], greaterThanOrEqualTo(191), reason: 'ρολόι');
      });
    });
  }
}
