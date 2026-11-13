// Έλεγχος 4/11, A10: κανόνες για το αντίγραφο Google και τη μεταφορά σε νέο κινητό. Μόνο ό,τι δεν ξαναδιαβάζεται
// (βάση, ρυθμίσεις, σχέδιο πηγών και ημερολόγιό του, νύχτες Oura)· ποτέ το βοηθητικό αρχείο, η ουρά σφαλμάτων ή tokens.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> includes(String xml) =>
    RegExp(r'<include domain="(\w+)" path="([^"]+)"').allMatches(xml).map((m) => '${m[1]}/${m[2]}').toSet();

void main() {
  const expected = {
    'database/ygeia.db',
    'database/ygeia.db-wal',
    'file/prefs.json',
    'file/sources.json',
    'file/sources_log.json',
    'file/oura_nights.json',
    'file/training.json',
    // Έλεγχος 9/11 (V-A-02): οι παλμοί κάθε προπόνησης σε δικό τους αρχείο.
    'file/hr/',
    // Round 1 (f8 · S9-10 / S10-3): η επιλογή «Αναφορές σφαλμάτων» (ένας διακόπτης) ακολουθεί τα δεδομένα.
    'sharedpref/errors.xml',
  };

  test('Κανόνες: ακριβώς τα αρχεία που δεν ξαναδιαβάζονται, ίδια στο Google και στη μεταφορά', () {
    final rules = File('tools/android/xml/data_extraction_rules.xml').readAsStringSync();
    final cloud = RegExp(r'<cloud-backup[^>]*>([\s\S]*?)</cloud-backup>').firstMatch(rules)![1]!;
    final transfer = RegExp(r'<device-transfer>([\s\S]*?)</device-transfer>').firstMatch(rules)![1]!;
    expect(includes(cloud), expected);
    expect(includes(transfer), expected);
    expect(includes(File('tools/android/xml/backup_rules.xml').readAsStringSync()), expected);
    for (final f in ['tools/android/xml/data_extraction_rules.xml', 'tools/android/xml/backup_rules.xml']) {
      final body = File(f).readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      for (final never in ['dashboard.json', 'errq', 'bg-failures', 'oura_tokens', 'oura_pending', 'no_backup', '.tmp', 'device_prefs']) {
        expect(body.contains(never), isFalse, reason: '$never στο $f');
      }
    }
  });

  // Έλεγχος 2, C14 (R9): 10 χρόνια δεδομένων υγείας στο Google μόνο με κρυπτογράφηση από άκρη σε άκρη.
  test('Αντίγραφο Google μόνο με κρυπτογράφηση από άκρη σε άκρη', () {
    final rules = File('tools/android/xml/data_extraction_rules.xml').readAsStringSync();
    expect(rules.contains('<cloud-backup disableIfNoEncryptionCapabilities="true">'), isTrue);
    final old = File('tools/android/xml/backup_rules.xml').readAsStringSync();
    final inc = RegExp(r'<include [^>]*>').allMatches(old).map((m) => m[0]!).toList();
    expect(inc, isNotEmpty);
    for (final i in inc) {
      expect(i.contains('requireFlags="clientSideEncryption"'), isTrue, reason: i);
    }
  });

  test('Το manifest δείχνει τους κανόνες και τα αρχεία μπαίνουν στο res/xml (δύο φορές = ίδιο αποτέλεσμα)', () {
    final dir = Directory.systemTemp.createTempSync('manifest');
    final m = File('${dir.path}/AndroidManifest.xml')
      ..writeAsStringSync('<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
          '    <application\n        android:label="ygeia_forma">\n'
          '        <activity\n            android:name=".MainActivity"\n            android:exported="true">\n'
          '        </activity>\n    </application>\n</manifest>\n');
    for (var i = 0; i < 2; i++) {
      final r = Process.runSync('python3', ['tools/android/patch_manifest.py', m.path]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    }
    final s = m.readAsStringSync();
    for (final a in [
      'android:allowBackup="true"',
      'android:fullBackupContent="@xml/backup_rules"',
      'android:dataExtractionRules="@xml/data_extraction_rules"',
    ]) {
      expect(RegExp(RegExp.escape(a)).allMatches(s).length, 1, reason: a);
    }
    expect(File('${dir.path}/res/xml/data_extraction_rules.xml').existsSync(), isTrue);
    expect(File('${dir.path}/res/xml/backup_rules.xml').existsSync(), isTrue);
    dir.deleteSync(recursive: true);
  });

  // Συγχώνευση 4/11: το όνομα της αναφοράς για τον γιατρό μένει ΜΟΝΟ στο κινητό. Η Kotlin το βγάζει από το prefs.json
  // (που μπαίνει στο αντίγραφο Google) και το γράφει στο noBackupFilesDir (DataRules.splitDeviceOnlyPrefs, έλεγχος
  // Kotlin reportNameStaysOnDeviceOutOfPrefsBackup).
  test('Όνομα αναφοράς: έξω από το prefs.json του αντιγράφου, στο noBackupFilesDir', () {
    final rules = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/DataRules.kt').readAsStringSync();
    expect(rules.contains('val DEVICE_ONLY_PREFS = setOf("reportName")'), isTrue);
    final bridge = File('android/app/src/main/kotlin/gr/ygeiaforma/ygeia_forma/SamsungHealthBridge.kt').readAsStringSync();
    expect(bridge.contains('DataRules.splitDeviceOnlyPrefs(json)'), isTrue);
    expect(bridge.contains('DataRules.mergeDeviceOnlyPrefs(shared, own)'), isTrue);
    expect(bridge.contains('activity.noBackupFilesDir, DataRules.DEVICE_PREFS_FILE'), isTrue);
  });
}
