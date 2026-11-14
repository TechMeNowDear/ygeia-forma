// Βαθύς έλεγχος 14/11, round 14 (εκδόσεις #113–#115): απόσταση ίδια με του ρολογιού, Πρόοδος και πίνακας ανά km μόνο
// με απόσταση GPS, σύνοψη για τον Claude με «≈», επαναφορά που κρατά τη φωνή κλειστή, κείμενα ζώνης και Σήμερα.
// Συνθετικά δεδομένα (όχι του χρήστη).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygeia_forma/data.dart' show todayCards;
import 'package:ygeia_forma/pages/settings.dart' show voiceSettingText;
import 'package:ygeia_forma/pages/training/zone_widgets.dart' show zoneHighText, zoneLowText, zoneVoiceText;
import 'package:ygeia_forma/training/progress.dart' show countsAsWalk;
import 'package:ygeia_forma/training/session.dart';
import 'package:ygeia_forma/training/training_store.dart';
import 'package:ygeia_forma/training/walk_stats.dart';
import 'package:ygeia_forma/training/zone.dart' show zoneBackSec, zoneGapSec;

Session _walk({double meters = 0, double? est, bool? gps = true, String id = 'w1', DateTime? start}) {
  final st = start ?? DateTime(2026, 11, 10, 18);
  return Session(
    id: id,
    workout: 'walk',
    name: 'Περπάτημα',
    programId: '',
    start: st,
    end: st.add(const Duration(minutes: 30)),
    cardioMinutes: 30,
    cardioSec: 1800,
    meters: meters,
    metersEst: est,
    steps: 3500,
    gps: gps,
    activity: 'walk',
    splits: [
      [600, 600],
      [1200, 1200],
    ],
    source: 'watch',
  );
}

void main() {
  group('1. απόσταση: το κινητό δείχνει ό,τι έδειξε το ρολόι', () {
    test('με «mest» (ρολόι #116: μόνο όταν έδειξε τα βήματα): η εκτίμηση και στο 60%', () {
      // Το ρολόι έμεινε στα βήματα (υστέρηση) με GPS 1.500 από 2.500: το κινητό το ίδιο.
      expect(pickMeters(1500, 2500, true), (meters: 2500.0, approx: true));
      // Χωρίς «mest» (το ρολόι έδειχνε GPS): το GPS, χωρίς «≈».
      expect(pickMeters(1500, 0, true), (meters: 1500.0, approx: false));
      // Το GPS στο 80% και πάνω: GPS (και για τα ρολόγια #114/#115 που στέλνουν πάντα «mest»).
      expect(pickMeters(2100, 2500, true), (meters: 2100.0, approx: false));
      // Μέσα στο σπίτι: 0 ή 6 m θόρυβος.
      expect(pickMeters(0, 584, true), (meters: 584.0, approx: true));
      expect(pickMeters(6, 584, true), (meters: 584.0, approx: true));
      // Κλειστή τοποθεσία: η απόσταση του ρολογιού από τα βήματα (Health Services), με «≈».
      expect(pickMeters(1500, 1440, false), (meters: 1500.0, approx: true));
      expect(pickMeters(0, 0, true), isNull);
      // Παλιό ρολόι (χωρίς «gps»): όπως GPS.
      expect(pickMeters(1500, 0, null), (meters: 1500.0, approx: false));
    });

    test('ζωντανά, ίδιος κανόνας', () {
      expect(liveMeters({'m': 1500, 'mest': 2500, 'gps': true}), (meters: 2500.0, approx: true));
      expect(liveMeters({'m': 1500, 'gps': true}), (meters: 1500.0, approx: false));
    });
  });

  group('2. Πρόοδος και πίνακας ανά km μόνο με απόσταση GPS', () {
    test('απόσταση από τα βήματα: ούτε στην Πρόοδο ούτε πίνακας ανά km', () {
      final gpsWalk = _walk(meters: 2400);
      expect(countsAsWalk(gpsWalk), isTrue);
      expect(walkSplits(gpsWalk), isNotEmpty);
      // GPS που «χάθηκε» μέσα σε κτίριο: 600 m GPS, εκτίμηση 2.500 από τα βήματα (τι έδειξε η σύνοψη: «≈ 2,50 km»).
      final drift = _walk(meters: 600, est: 2500);
      expect(kmValue(drift), '≈ 2,50');
      expect(countsAsWalk(drift), isFalse);
      expect(walkSplits(drift), isEmpty);
    });
  });

  group('3. σύνοψη για τον Claude: η απόσταση των οθονών', () {
    test('με «≈» όταν μέρος της είναι από τα βήματα', () {
      final now = DateTime(2026, 11, 14, 20);
      final t = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      t.sessions.addAll([
        _walk(id: 'a', meters: 0, est: 584, start: DateTime(2026, 11, 13, 18)),
        _walk(id: 'b', meters: 2180, start: DateTime(2026, 11, 12, 18)),
      ]);
      final text = t.exportForClaude();
      // 0,584 + 2,18 = 2,764 → «≈ 2,8 km» (πριν «2,2 km»: μόνο τα μέτρα του GPS).
      expect(text, contains('≈ 2,8 km'));
    });
  });

  group('4. επαναφορά από αντίγραφο', () {
    test('φωνή κλειστή στο αντίγραφο → κλειστή και μετά την επαναφορά', () async {
      final now = DateTime(2026, 11, 14, 20);
      final src = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      src.setVoice(false);
      final fresh = TrainingStore(io: MemoryTrainingIO(), clock: () => now);
      await fresh.load();
      expect(fresh.voice, isTrue);
      fresh.mergeBackup(src.toJson());
      expect(fresh.voice, isFalse);
      // Ανοιχτή στο αντίγραφο: δεν ανοίγει όσα έκλεισες εδώ.
      final on = TrainingStore(io: MemoryTrainingIO(), clock: () => now)..ready = true;
      fresh.mergeBackup(on.toJson());
      expect(fresh.voice, isFalse);
    });
  });

  group('5. κείμενα ζώνης και φωνής ίδια με το ρολόι', () {
    test('φωνή και στις δύο μεριές, «Πάλι στη ζώνη» μετά από 10″, όχι πιο συχνά από 1 λεπτό', () {
      expect(zoneGapSec, 60);
      expect(zoneBackSec, 10);
      expect(zoneHighText, contains('ποτέ πιο συχνά από 1 λεπτό'));
      expect(zoneLowText, contains('«Εκτός εύρους»'));
      expect(zoneVoiceText, contains('«Πάλι στη ζώνη» όταν ξαναμπείς για 10 δευτερόλεπτα'));
      expect(zoneVoiceText, contains('«Φωνή στην άσκηση»'));
      // Πιο σύντομο, και το «ρολόι» μία φορά.
      expect(RegExp('ρολογιού|ρολόι').allMatches(voiceSettingText).length, 1);
      // Ίδιες τιμές με το ρολόι.
      final kt = File('android/wear/src/main/kotlin/gr/ygeiaforma/wear/Protocol.kt').readAsStringSync();
      expect(kt, contains('const val ZONE_GAP_MS = 60_000L'));
      expect(kt, contains('const val ZONE_BACK_MS = 10_000L'));
    });
  });

  group('6. Σήμερα', () {
    final src = File('lib/pages/today.dart').readAsStringSync();
    test('κάθε κάρτα στην ενότητά της, όχι «Επίσης»· η μόνη σε όλο το πλάτος', () {
      expect(src, isNot(contains("section('Επίσης'")));
      expect(src, contains('if (cards.length.isOdd) IntrinsicHeight(child: cards.last),'));
      expect(todayCards.firstWhere((c) => c.key == 'awake').label, contains('τελευταίας ολόκληρης μέρας'));
    });
    test('Άσκηση: μόνο αφού διαβαστούν οι προπονήσεις· και χωρίς την άδεια της Samsung', () {
      expect(src, contains('final known = training.ready && !training.readError;'));
      expect(src, contains("subtitle: 'από Δευτέρα',"));
      expect("'today-exweek'".allMatches(src).length, 1);
      expect(RegExp(r"_exerciseWeekCard\(context, training, now").allMatches(src).length, 2);
    });
    test('Λίπος: η ζύγιση που δείχνει και το Βάρος, με τα ίδια κείμενα', () {
      final fat = src.substring(src.indexOf('Widget _fatCard('), src.indexOf('Widget _energyCard('));
      expect(fat, contains('guard.shown'));
      expect(fat, contains('pendingWeightNote'));
      expect(fat, contains("d.failed.contains('body')"));
    });
  });
}
