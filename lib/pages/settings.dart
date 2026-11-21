import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../backup.dart';
import '../data.dart';
import '../error_report.dart' show errors;
import '../food/food_channel.dart';
import '../food/food_store.dart';
import '../format.dart';
import '../history.dart' show otherDeviceNights;
import '../theme.dart';
import '../sources.dart';
import '../ti_ftanei.dart';
import '../training/training_store.dart';
import '../training/wear_link.dart' show WearLink, ymd;
import '../widgets.dart';
import '../vitals.dart' show VitalsStore;
import 'ai_settings.dart';
import 'appearance.dart';
import 'devices_page.dart';
import 'diagnostics_sheet.dart';
import 'sources_page.dart';
import 'me_page.dart';
import 'privacy_page.dart';
import 'training/training_page.dart' show editDoctorLimit;
import 'cloud_backup_size.dart';

/// Το κείμενο στο τέλος των Ρυθμίσεων. Έλεγχος 13/11 (U4-8): έγραφε «διαβάζει δεδομένα μόνο όταν την ανοίγεις», ενώ από
/// τις 2/11 η εφαρμογή διαβάζει το Samsung Health και κάθε 3 ώρες στο παρασκήνιο (RefreshWorker.kt· όχι 00:00–06:00).
const settingsFooterText = 'Υγεία & Φόρμα ·\u00A0προσωπική έκδοση\n'
    'Η εφαρμογή διαβάζει το Samsung Health όταν την ανοίγεις και, για να είναι έτοιμη, περίπου κάθε 3 ώρες χωρίς να την '
    'ανοίξεις (όχι από τα μεσάνυχτα ως τις 6 το πρωί).';

/// Το αποτέλεσμα μιας εξαγωγής αντιγράφου: [ok] μόνο για πλήρες αντίγραφο που γράφτηκε· [text] για τον χρήστη· [uri] το
/// αρχείο στις Λήψεις, για την «Αποστολή».
typedef BackupExport = ({bool ok, String text, String? uri});

/// Οι προπονήσεις για το αντίγραφο, με τους παλμούς τους (μόνο αν διαβάστηκαν σωστά).
Future<Map<String, dynamic>?> _trainingForBackup() async {
  final t = TrainingStore.main;
  await t.load();
  return t.ready && !t.readError ? await t.backupJson() : null;
}

/// Η εξαγωγή χωρίς μηνύματα. Τη χρησιμοποιούν η γραμμή «Εξαγωγή αντιγράφου» (μήνυμα κάτω), το φύλλο «Διαγραφή όλων»
/// (μέσα στο φύλλο, έλεγχος του fix-accuracy, M2) και η κάρτα «Αντίγραφο ασφαλείας» της «Σήμερα» (έλεγχος 13/11, S9-3).
Future<BackupExport> exportBackupNow(HealthStore store, FoodStore food) async {
  final raw = await food.exportRaw();
  if (raw == null) return (ok: false, text: 'Δεν διαβάστηκαν τα δεδομένα. Δοκίμασε ξανά.', uri: null);
  // Πίεση, σάκχαρο, καρδιογραφήματα (16/11, έλεγχος): να έχουν διαβαστεί πριν μπουν στο αρχείο.
  await VitalsStore.main.ensureLoaded();
  final now = DateTime.now();
  final name = backupFileName(now);
  final sources = await store.sourcesForBackup();
  // Οι ρυθμίσεις μπαίνουν μόνο αν έχουν διαβαστεί (αλλιώς θα έμπαιναν οι αρχικές).
  // 18/11: η κωδικοποίηση σε άλλο isolate (όπως ήδη η ανάγνωση στην επαναφορά), ώστε ένα αντίγραφο χρόνων να μην
  // «κολλάει» την οθόνη. Οι τιμές μαζεύονται πρώτα εδώ· στο isolate περνούν μόνο απλοί χάρτες και λίστες.
  final BackupArgs args = (
    foodLog: raw.$1,
    myFoods: raw.$2,
    prefs: store.prefsLoaded ? store.prefsJson() : const <String, dynamic>{},
    now: now,
    sources: sources,
    training: await _trainingForBackup(),
    // «Τα φαγητά μου» (15/11).
    dishes: food.dishesForBackup(),
    foodLikes: food.likesForBackup(),
    foodDays: food.dishesRead ? food.dayMarksForBackup() : null,
    foodUnits: food.dishesRead ? food.unitsForBackup() : null,
    vitals: VitalsStore.main.read ? VitalsStore.main.forBackup() : null,
    foodWeek: food.dishesRead ? food.weekForBackup() : null,
    foodRemind: food.dishesRead ? food.remindAt : null,
    history: store.historyForBackup(),
    // Round 7 (R7-A11-4): η αντίρρηση στις αναφορές σφαλμάτων ταξιδεύει με το αντίγραφο.
    errorsOff: !errors.enabled,
  );
  final json = await compute(buildBackupFrom, args);
  final dishesOut = !food.dishesRead;
  final vitalsOut = !VitalsStore.main.read;
  // Έλεγχος 17/11 (Κ8-M2): το ιστορικό ημερών έχει και ό,τι δεν ξαναδιαβάζεται από τη Samsung.
  final historyOut = !store.historyReady;
  final dishCount = food.dishesForBackup()?.length ?? 0;
  final trainingOut = TrainingStore.main.readError;
  final hrMissing = trainingOut ? 0 : TrainingStore.main.backupHrMissing;
  // Έλεγχος 13/11 (S9-8): αν οι ρυθμίσεις δεν διαβάστηκαν (ή ισχύουν οι προεπιλογές, γιατί το αρχείο τους χάλασε), το
  // αρχείο ΔΕΝ έχει «Τα στοιχεία μου», στόχους, ζώνη και μέση· αν το σχέδιο πηγών δεν διαβάζεται, δεν έχει το από πότε
  // μετρά το Oura. Πριν, έβγαινε πράσινο «Αποθηκεύτηκε» και άνοιγε η «Διαγραφή όλων» με μισό αντίγραφο. (Κινητό που δεν
  // είχε ποτέ Oura δεν έχει σχέδιο να μπει: εκεί δεν λείπει τίποτα.)
  final prefsOut = !store.prefsLoaded || store.prefsFromDefaults;
  final sourcesOut = sources == null && (!store.planReady || store.plan.eras.isNotEmpty);
  final r = await FoodChannel.saveBackup(json, name);
  if (r['ok'] != true || r['uri'] is! String) {
    // Round 7 (R7-A9-5): ελληνικό μήνυμα από το είδος του σφάλματος, ποτέ το κείμενο της Java.
    return (ok: false, text: backupSaveFailText(r), uri: null);
  }
  final saved = r['name'] is String ? r['name'] as String : name;
  // Πλήρες μόνο αν μπήκαν οι προπονήσεις με τους παλμούς τους, οι ρυθμίσεις και οι πηγές ύπνου. Μόνο ένα πλήρες
  // αντίγραφο μετρά ως «τελευταίο αντίγραφο» (13/11).
  final complete = !trainingOut && hrMissing == 0 && !prefsOut && !sourcesOut && !dishesOut && !vitalsOut && !historyOut;
  if (complete) store.markExported(now);
  return (
    ok: complete,
    text: 'Αποθηκεύτηκε στις Λήψεις: $saved ·\u00A0${entriesText(raw.$1.length)}, ${productsText(raw.$2.length)}'
        '${dishCount > 0 ? ', ${dishesText(dishCount)}' : ''}'
        '${dishesOut ? '. «Τα φαγητά μου» δεν μπήκαν: δεν διαβάστηκαν.' : ''}'
        '${vitalsOut ? '. Πίεση, σάκχαρο και καρδιογραφήματα δεν μπήκαν: δεν διαβάστηκαν.' : ''}'
        // Έλεγχος 9/11 (V-A-10): να μη λείπουν σιωπηλά.
        '${trainingOut ? '. Οι προπονήσεις δεν μπήκαν: το αρχείο τους δεν διαβάζεται.' : ''}'
        // Έλεγχος του #91 (S5): προπονήσεις των οποίων οι παλμοί δεν διαβάστηκαν, να μη λείπουν σιωπηλά.
        '${hrMissing > 0 ? '. ${countText(hrMissing, 'προπόνηση μπήκε χωρίς παλμούς', 'προπονήσεις μπήκαν χωρίς παλμούς')}: τα αρχεία τους δεν διαβάστηκαν.' : ''}'
        '${prefsOut ? '. Οι ρυθμίσεις (στοιχεία, στόχοι, μέση) δεν μπήκαν: δεν διαβάστηκαν.' : ''}'
        '${sourcesOut ? '. Οι πηγές ύπνου δεν μπήκαν: δεν διαβάστηκαν.' : ''}'
        '${historyOut ? '. Το ιστορικό ημερών δεν μπήκε: δεν διαβάστηκε.' : ''}'
        // Έλεγχος 13/11 (S9-3): το αρχείο μένει στις Λήψεις του ίδιου κινητού.
        '${complete ? '. Στείλ’ το και έξω από το κινητό (π.χ. στο Drive ή με email).' : ''}',
    uri: r['uri'] as String,
  );
}

/// Round 2 (R2-B-3): η επαναφορά μπήκε στη μνήμη, αλλά δεν γράφτηκε στο κινητό (ίδιο με την κάρτα της Σήμερα).
const restorePrefsUnsavedText =
    'Οι ρυθμίσεις του αντιγράφου μπήκαν, αλλά δεν γράφτηκαν στο κινητό· πάτα «Δοκίμασε ξανά» στη Σήμερα.';

/// Round 2 (R2-B-3): τι λέει η σύνοψη της επαναφοράς για τις ρυθμίσεις. [ok]: γράφτηκαν (ή το αντίγραφο δεν είχε)·
/// [loaded]: οι ρυθμίσεις του κινητού είχαν διαβαστεί πριν από την επαναφορά (αλλιώς δεν αλλάζει τίποτα)· [unsaved]:
/// [HealthStore.prefsSaveError] τη στιγμή της σύνοψης· [notes]: τι από στόχους/ζώνη δεν μπήκε (S9-11). «Δεν άλλαξαν»
/// μόνο όταν πράγματι δεν άλλαξαν· πριν το έλεγε και όταν μπήκαν στη μνήμη αλλά δεν γράφτηκαν (π.χ. γεμάτος χώρος),
/// ενώ η κάρτα της Σήμερα έλεγε «τη βλέπεις στην οθόνη».
List<String> restorePrefsSummary(
    {required bool ok, required bool loaded, required bool unsaved, required List<String> notes}) {
  if (!ok && !loaded) return const ['Οι ρυθμίσεις δεν άλλαξαν.'];
  return [if (!ok && unsaved) restorePrefsUnsavedText, ...notes];
}

/// Round 7 (R7-A9-3): τι λέει η σύνοψη της επαναφοράς για τις πηγές ύπνου, για κάθε λόγο χωριστά. Πριν έλεγε «του
/// κινητού είναι νεότερες» και όταν οι πηγές του κινητού δεν διαβάζονταν ή δεν γράφτηκαν: ακριβώς τότε που οι νύχτες
/// μένουν χωρίς σωστή πηγή και η επαναφορά πρέπει να ξαναγίνει.
String sourcesRestoreText(SourcesRestore r) => switch (r) {
      SourcesRestore.restored => 'Οι πηγές ύπνου μπήκαν από το αντίγραφο.',
      SourcesRestore.phoneNewer => 'Οι πηγές ύπνου του κινητού είναι νεότερες και έμειναν.',
      SourcesRestore.same => 'Οι πηγές ύπνου του κινητού είναι ίδιες με του αντιγράφου.',
      SourcesRestore.notReady =>
        'Οι πηγές ύπνου δεν μπήκαν: οι ρυθμίσεις ή οι πηγές του κινητού δεν διαβάζονται ακόμα. Κάνε ξανά την επαναφορά σε λίγο.',
      SourcesRestore.writeFailed => 'Οι πηγές ύπνου δεν γράφτηκαν στο κινητό. Κάνε ξανά την επαναφορά.',
      SourcesRestore.invalid => 'Οι πηγές ύπνου του αντιγράφου δεν διαβάζονται· έμειναν του κινητού.',
    };

/// Round 7 (R7-A11-4): το αντίγραφο είχε κλειστές τις αναφορές σφαλμάτων, και έκλεισαν και εδώ.
const restoreErrorsClosedText = 'Οι αναφορές σφαλμάτων έμειναν κλειστές, όπως στο αντίγραφο.';

/// Round 8 (R8-U4-5): η επαναφορά σταμάτησε γιατί δεν διαβάστηκε τι υπάρχει ήδη στο κινητό. Αν όμως πρόλαβαν να κλείσουν
/// οι αναφορές σφαλμάτων ([errorsClosed], γίνεται πρώτο), το λέει· πριν έλεγε «δεν άλλαξε τίποτα» και τότε.
String restoreNotReadText({required bool errorsClosed}) => errorsClosed
    ? 'Δεν διαβάστηκε τι υπάρχει ήδη στο κινητό. Οι αναφορές σφαλμάτων έκλεισαν, όπως στο αντίγραφο· τίποτα άλλο δεν άλλαξε. '
        'Δοκίμασε ξανά.'
    : 'Δεν διαβάστηκε τι υπάρχει ήδη στο κινητό, οπότε δεν άλλαξε τίποτα. Δοκίμασε ξανά.';

/// «Δοκιμή φωνής» (αίτημα χρήστη 15/11): πού ακούστηκε, από τον κωδικό του ρολογιού (android/wear/…/Protocol.kt:
/// VoiceTest). Χωρίς κωδικό που να ξέρουμε: το ηχείο του ρολογιού (ό,τι κάνει το ρολόι όταν δεν το λέει αλλού).
String voiceTestText(String code) => switch (code) {
      'wh' => 'στα ακουστικά του ρολογιού',
      'ph' => 'στα ακουστικά του κινητού',
      'nv' => 'πουθενά: δεν βρέθηκε φωνή στο ρολόι',
      'mu' => 'πουθενά: το ρολόι δεν πήρε άδεια να μιλήσει',
      'm0' => 'πουθενά: η ένταση πολυμέσων του ρολογιού είναι στο μηδέν',
      'bz' => 'δεν έγινε: έτρεχε άσκηση στο ρολόι',
      _ => 'από το ηχείο του ρολογιού',
    };

/// Η γραμμή κάτω από το «Δοκιμή φωνής»: γιατί δεν πατιέται, ή τι έγινε την τελευταία φορά, ή τι κάνει.
String voiceTestSubtitle({
  required bool voiceOn,
  required bool watchNear,
  required bool watchKnows,
  required ({DateTime at, String code})? last,
  required DateTime now,
}) {
  if (!voiceOn) return 'Άνοιξε πρώτα τη «Φωνή στην άσκηση».';
  if (!watchNear) return 'Χρειάζεται το ρολόι κοντά, με την εφαρμογή.';
  if (!watchKnows) return 'Άνοιξε μία φορά την εφαρμογή στο ρολόι (χρειάζεται την έκδοση 119 ή νεότερη).';
  if (last != null) {
    final at = last.at;
    final when = ymd(at) == ymd(now) ? hm(at) : '${at.day}/${at.month} ${hm(at)}';
    return 'Τελευταία δοκιμή $when: ${voiceTestText(last.code)}.';
  }
  return 'Το ρολόι λέει «Δοκιμή φωνής» όπως στο περπάτημα, για να ακούσεις από πού βγαίνει.';
}

/// Μόλις πατηθεί: τι κάνει τώρα ο χρήστης. Η εφαρμογή του κινητού πρέπει να είναι κλειστή, όπως στο περπάτημα.
const voiceTestGoText = 'Πάτα τώρα το κουμπί της αρχικής οθόνης. Σε 10 δευτερόλεπτα θα ακούσεις «Δοκιμή φωνής». '
    'Μετά άνοιξε ξανά την εφαρμογή: εδώ θα γράφει από πού ακούστηκε.';

/// Η εξήγηση κάτω από τη «Φωνή στην άσκηση» (14/11).
// Round 14 (U9): πιο σύντομο (πριν 5 γραμμές στα 400 dp), και το «ρολόι» μία φορά, με ένα νόημα.
const voiceSettingText = 'Κάθε χιλιόμετρο, «Πάνω από τη ζώνη», «Κάτω από τη ζώνη», παύση, επόμενο σετ. Στα ακουστικά σου, αλλιώς στο ηχείο του '
    'ρολογιού· η μουσική χαμηλώνει για λίγο.';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store, this.food});
  final HealthStore store;

  /// Για το αντίγραφο ασφαλείας (ημερολόγιο φαγητού και προϊόντα).
  final FoodStore? food;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    // Σχέδιο «Settings» (premium, 10/11): γραμμές σε ενότητες, με «Τι μετράει κάθε συσκευή» (DevicesPage του premium).
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ρυθμίσεις'),
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final d = store.data;
          void push(String name, Widget Function(BuildContext) b) =>
              Navigator.of(context).push(MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: b));
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SettingsGroup(children: [
                        SettingsRow(
                          icon: Icons.palette_outlined,
                          title: 'Εμφάνιση',
                          subtitle: switch (store.prefs.themeMode) {
                            'light' => 'Πάντα φωτεινό ·\u00A0${Aigaio.day(store.prefs.dayTheme).name}',
                            'dark' => 'Πάντα σκοτεινό ·\u00A0${Aigaio.night(store.prefs.nightTheme).name}',
                            _ => 'Μέρα ${Aigaio.day(store.prefs.dayTheme).name} ·\u00A0'
                                'νύχτα ${Aigaio.night(store.prefs.nightTheme).name}',
                          },
                          onTap: () => push('Εμφάνιση', (_) => AppearancePage(store: store)),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-me'),
                          icon: Icons.person_outline_rounded,
                          title: 'Τα στοιχεία μου',
                          // Σχέδιο Settings + premium: η κουζίνα και τα προϊόντα μου είναι πια μέσα στα «Τα στοιχεία μου».
                          subtitle: 'Ηλικία, ύψος, ζυγίσεις, στόχοι ·\u00A0η κουζίνα μου ·\u00A0τα προϊόντα μου',
                          onTap: () => Navigator.of(context).push(MePage.route(store)),
                        ),
                        // 19/11: AI μόνο για το φαγητό (πρόγραμμα εβδομάδας, αλλαγή γεύματος).
                        SettingsRow(
                          key: const ValueKey('settings-ai'),
                          icon: Icons.auto_awesome_outlined,
                          title: 'AI για το φαγητό',
                          subtitle: 'Σύνδεση με τη γέφυρα ·\u00A0τι στέλνεται',
                          onTap: () => push('AI για το φαγητό', (_) => const AiSettingsPage()),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-today-cards'),
                          icon: Icons.grid_view_rounded,
                          title: 'Κάρτες της «Σήμερα»',
                          subtitle: 'Τι εμφανίζεται',
                          onTap: () => push('Κάρτες της Σήμερα', (_) => TodayCardsPage(store: store)),
                        ),
                        // 14/11 (αίτημα χρήστη): φωνή από το ρολόι στην άσκηση. Ανοιχτή από προεπιλογή· κλείνει εδώ (π.χ. σε
                        // σύσκεψη). Πάει στο ρολόι με το πρόγραμμα.
                        ListenableBuilder(
                          listenable: TrainingStore.main,
                          builder: (context, _) {
                            final t = TrainingStore.main;
                            final ready = t.ready && !t.readError;
                            return SettingsRow(
                              key: const ValueKey('settings-voice'),
                              icon: Icons.record_voice_over_outlined,
                              title: 'Φωνή στην άσκηση',
                              subtitle: voiceSettingText,
                              trailing: Switch(
                                key: const ValueKey('settings-voice-switch'),
                                value: ready && t.voice,
                                onChanged: ready ? t.setVoice : null,
                              ),
                              onTap: ready ? () => t.setVoice(!t.voice) : null,
                            );
                          },
                        ),
                        // 15/11 (αίτημα χρήστη): «Δοκιμή φωνής». Το ρολόι λέει τη φράση με τον δρόμο του περπατήματος ενώ η
                        // εφαρμογή εδώ είναι κλειστή (όπως στο περπάτημα· με την εφαρμογή ανοιχτή θα έβγαινε πάντα στα
                        // ακουστικά του κινητού και η δοκιμή θα έλεγε ψέματα). Το αποτέλεσμα έρχεται από το ρολόι.
                        ListenableBuilder(
                          listenable: Listenable.merge([
                            TrainingStore.main,
                            WearLink.main.ready,
                            WearLink.main.watchVoiceTest,
                            WearLink.main.voiceTest,
                          ]),
                          builder: (context, _) {
                            final t = TrainingStore.main;
                            final w = WearLink.main;
                            final voiceOn = t.ready && !t.readError && t.voice;
                            final can = voiceOn && w.ready.value && w.watchVoiceTest.value;
                            return SettingsRow(
                              key: const ValueKey('settings-voice-test'),
                              icon: Icons.hearing_outlined,
                              title: 'Δοκιμή φωνής',
                              subtitle: voiceTestSubtitle(
                                voiceOn: voiceOn,
                                watchNear: w.ready.value,
                                watchKnows: w.watchVoiceTest.value,
                                last: w.voiceTest.value,
                                now: DateTime.now(),
                              ),
                              onTap: can
                                  ? () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      final ok = await w.startVoiceTest();
                                      messenger.showSnackBar(SnackBar(
                                        content: Text(ok
                                            ? voiceTestGoText
                                            : 'Δεν βρέθηκε το ρολόι. Άνοιξε την εφαρμογή στο ρολόι και ξαναδοκίμασε.'),
                                        persist: false,
                                        duration: const Duration(seconds: 10),
                                      ));
                                    }
                                  : null,
                            );
                          },
                        ),
                      ]),
                      const SettingsSection('Απόρρητο'),
                      const PrivacyGroup(),
                      const SettingsSection('Τα δεδομένα μου'),
                      _DataGroup(store: store, food: food),
                      const SettingsSection('Για προχωρημένους'),
                      SettingsGroup(children: [
                        SettingsRow(
                          key: const ValueKey('settings-sources'),
                          icon: Icons.link_rounded,
                          color: c.textSecondary,
                          title: 'Πηγές',
                          subtitle: 'Ύπνος: ${sourceDevice(store.plan.nightSource(DateTime.now()))} ·\u00A0'
                              'βήματα: Samsung Health ·\u00A0βάρος: InBody',
                          onTap: () => Navigator.of(context).push(SourcesPage.route(store)),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-devices'),
                          icon: Icons.layers_rounded,
                          color: c.textSecondary,
                          title: 'Τι μετράει κάθε συσκευή',
                          subtitle: 'Μέτρηση, εκτίμηση, ενδεικτικό',
                          onTap: () => Navigator.of(context).push(DevicesPage.route()),
                        ),
                        // Σχέδια 12/11 (5δ): το όριο παλμών του γιατρού δεν είναι πια στην Προπόνηση (συνήθως δεν δίνεται)·
                        // μένει εδώ για όποιον έχει. Αν υπάρχει, φαίνεται ΚΑΙ στην Προπόνηση και νικά τη ζώνη στο ρολόι.
                        ListenableBuilder(
                          listenable: TrainingStore.main,
                          builder: (context, _) {
                            final hr = TrainingStore.main.ready ? TrainingStore.main.hrLimit : null;
                            return SettingsRow(
                              key: const ValueKey('settings-hrlimit'),
                              icon: Icons.favorite_border_rounded,
                              color: c.textSecondary,
                              title: 'Όριο παλμών από τον γιατρό',
                              subtitle: hr == null ? 'Κανένα ·\u00A0μόνο αν σου έδωσε γιατρός' : '$hr bpm ·\u00A0δόνηση στο ρολόι όσο μετρά άσκηση',
                              onTap: () async {
                                await TrainingStore.main.load();
                                if (context.mounted) await editDoctorLimit(context, TrainingStore.main);
                              },
                            );
                          },
                        ),
                        SettingsRow(
                          icon: Icons.build_outlined,
                          color: c.textSecondary,
                          title: 'Έλεγχος δεδομένων',
                          subtitle: '«Τι φτάνει» από κάθε πηγή',
                          onTap: () => push(
                            'Έλεγχος δεδομένων',
                            (_) => Scaffold(
                              appBar: AppBar(title: const Text('Έλεγχος δεδομένων')),
                              body: TiFtaneiScreen(otherDeviceNights: otherDeviceNights(store.history)),
                            ),
                          ),
                        ),
                        SettingsRow(
                          icon: Icons.watch_outlined,
                          color: c.textSecondary,
                          title: 'Άδειες Samsung Health',
                          subtitle: d == null
                              ? '—'
                              : '${d.granted} από ${d.total} ·\u00A0ανάγνωση ${relativeDay(d.readAt, DateTime.now())} ${hm(d.readAt)}',
                          onTap: () => store.refresh(askPermissions: true),
                        ),
                        SettingsRow(
                          key: const ValueKey('settings-licenses'),
                          icon: Icons.description_outlined,
                          color: c.textSecondary,
                          title: 'Άδειες λογισμικού',
                          subtitle: 'Γραμματοσειρά Inter, βιβλιοθήκες',
                          onTap: () => openLicenses(context),
                        ),
                      ]),
                      const SizedBox(height: 20),
                      Text(
                        settingsFooterText,
                        key: const ValueKey('settings-footer'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Round 9 (R9-U4-8, f4): οι κάρτες της «Σήμερα» που με το Oura δεν εμφανίζονται ποτέ (today.dart: `!ouraNight && …`):
/// Energy Score (τη θέση του παίρνει η ετοιμότητα του Oura), παλμοί και θερμοκρασία ύπνου. Οι διακόπτες τους δεν
/// έκαναν τίποτα· τώρα δεν φαίνονται και η σελίδα λέει πού είναι αυτά ([todayCardsOuraNote]).
const ouraHiddenTodayCards = {'energy', 'rhr', 'skin'};

/// Οι κάρτες με διακόπτη στη σελίδα «Κάρτες της Σήμερα», για τη νύχτα του [now] ([plan]: από πού έρχεται η νύχτα).
List<TodayCard> todayCardsToChoose(SourcePlan plan, DateTime now) {
  final oura = plan.nightSource(now) != Source.watch;
  return [for (final c in todayCards) if (!oura || !ouraHiddenTodayCards.contains(c.key)) c];
}

/// Τι λέει η σελίδα με το Oura, στη θέση των τριών διακοπτών. Η κάρτα «Ύπνος της νύχτας» έχει «Ετοιμότητα · HRV ·
/// Παλμοί ύπνου» (oura_today.dart)· η θερμοκρασία είναι στην Υγεία › Ύπνος.
const todayCardsOuraNote = 'Με το Oura, η ετοιμότητα και οι παλμοί ύπνου φαίνονται μέσα στην κάρτα «Ύπνος της '
    'νύχτας» και η θερμοκρασία στην Υγεία › Ύπνος.';

/// «Κάρτες της Σήμερα»: τι εμφανίζεται (πριν: κάρτα με διακόπτες μέσα στις Ρυθμίσεις).
class TodayCardsPage extends StatelessWidget {
  const TodayCardsPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Κάρτες της «Σήμερα»'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final shown = todayCardsToChoose(store.plan, DateTime.now());
          return ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Τα δεδομένα διαβάζονται όλα· εδώ διαλέγεις μόνο τι εμφανίζεται.',
                      style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4)),
                  for (final card in shown)
                    SwitchListTile(
                      contentPadding: const EdgeInsets.only(right: 4),
                      title: Text(card.label),
                      value: store.prefs.show(card.key),
                      onChanged: (on) => store.setCard(card.key, on),
                    ),
                  if (shown.length < todayCards.length)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                      child: Text(todayCardsOuraNote,
                          key: const ValueKey('today-cards-oura-note'),
                          style: TextStyle(color: c.textSecondary, fontSize: 13.5, height: 1.4)),
                    ),
                ]),
              ),
            ),
          ),
        ]);
        },
      ),
    );
  }
}

/// «ΤΑ ΔΕΔΟΜΕΝΑ ΜΟΥ»: αντίγραφο ασφαλείας (όσα υπάρχουν μόνο σε αυτό το κινητό) και «Διαγραφή όλων».
class _DataGroup extends StatefulWidget {
  const _DataGroup({required this.store, required this.food});
  final HealthStore store;
  final FoodStore? food;

  @override
  State<_DataGroup> createState() => _DataGroupState();
}

class _DataGroupState extends State<_DataGroup> {
  bool _busy = false;

  void _say(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    // Round8 (R8-U2-1, f1): με κουμπί («Αποστολή») το μήνυμα δεν θα έκλεινε ποτέ μόνο του (Flutter ≥ 3.38).
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), action: action, persist: false, duration: const Duration(seconds: 6)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final r = await exportBackupNow(widget.store, widget.food!);
      final uri = r.uri;
      _say(r.text, action: uri == null ? null : SnackBarAction(label: 'Αποστολή', onPressed: () => FoodChannel.shareBackup(uri)));
    } catch (_) {
      // Έλεγχος 19/11 (IS-3): όπως η κάρτα της Σήμερα· πριν το σφάλμα δεν έλεγε τίποτα.
      _say('Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Για το φύλλο «Διαγραφή όλων»: το αποτέλεσμα γυρίζει στο φύλλο (το SnackBar θα ήταν κάτω από αυτό).
  Future<BackupResult> _exportForWipe() async {
    try {
      final r = await exportBackupNow(widget.store, widget.food!);
      return (ok: r.ok, text: r.text);
    } catch (_) {
      return (ok: false, text: 'Δεν αποθηκεύτηκε το αντίγραφο. Δοκίμασε ξανά.');
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await FoodChannel.pickBackup();
      if (r['ok'] != true) {
        if (r['kind'] != 'cancelled') _say(backupOpenFailText(r));
        return;
      }
      BackupContents? parsed;
      try {
        // Σε ξεχωριστό νήμα: ένα αντίγραφο χρόνων είναι αρκετά MB και δεν πρέπει να «παγώσει» η οθόνη.
        parsed = await compute(parseBackup, r['json'] as String? ?? '');
      } on BackupError catch (e) {
        _say(e.message);
      } catch (_) {
        // Τελικός έλεγχος (Συμβούλιο 3): οποιοδήποτε άλλο σφάλμα ανάγνωσης λέγεται κι αυτό. Πριν, η επαναφορά σταματούσε
        // χωρίς κανένα μήνυμα.
        _say('Το αρχείο δεν είναι αντίγραφο της εφαρμογής.');
      }
      if (parsed == null) return;
      final b = parsed;
      if (!mounted) return;
      final when = b.created == null ? '' : ' της ${shortDayDate(b.created!.toLocal())}';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Επαναφορά αντιγράφου'),
          content: Text(
            'Αντίγραφο$when: ${entriesText(b.entries.length)} φαγητού, ${productsText(b.myFoods.length)}'
            '${b.dishes.isEmpty ? '' : ', ${dishesText(b.dishes.length)}'}.\n\n'
            'Μπαίνουν μόνο όσα λείπουν από το κινητό. Όσα υπάρχουν ήδη μένουν όπως είναι, με όσες αλλαγές τους έκανες. '
            'Τίποτα δεν σβήνεται· καταχωρίσεις που έσβησες μετά το αντίγραφο ξαναμπαίνουν.'
            '${b.prefs.isEmpty ? '' : '\n\nΘα αντικατασταθούν οι ρυθμίσεις: «Η κουζίνα μου», οι κάρτες της Σήμερα και η εμφάνιση.'}'
            '${b.sources == null ? '' : '\n\nΠηγές ύπνου (π.χ. από πότε μετρά το Oura): από το αντίγραφο, μόνο αν το κινητό δεν έχει νεότερες.'}'
            '${b.training == null ? '' : '\n\nΠροπονήσεις: μπαίνουν όσες λείπουν. Το όριο παλμών του γιατρού δεν μπαίνει· το ξαναγράφεις.'}'
            '${b.skipped == 0 ? '' : '\n\n${countText(b.skipped, 'χαλασμένη εγγραφή θα παραλειφθεί', 'χαλασμένες εγγραφές θα παραλειφθούν')}.'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Επαναφορά')),
          ],
        ),
      );
      if (ok != true) return;
      // Round 7 (R7-A11-4): πρώτα η αντίρρηση στις αναφορές σφαλμάτων (αν το αντίγραφο την είχε), πριν από οτιδήποτε άλλο.
      final errorsClosed = await restoreErrorsChoice(b, errors);
      final res = await widget.food!.importBackup(b.entries, b.myFoods);
      if (res == null) {
        _say(restoreNotReadText(errorsClosed: errorsClosed));
        return;
      }
      final (e, f, failed, existing) = res;
      // «Τα φαγητά μου» (15/11): μπαίνουν όσα λείπουν· ό,τι υπάρχει ήδη μένει όπως είναι.
      final dishRes = b.dishes.isEmpty ? null : await widget.food!.importDishes(b.dishes);
      final likesIn = await widget.food!.importLikes(b.likes);
      // «Τελείωσα για σήμερα» (16/11): μόνο οι μέρες χωρίς σημάδι στο κινητό.
      final marksIn = await widget.food!.importDayMarks(b.dayMarks);
      final unitsIn = await widget.food!.importUnits(b.units);
      final weekIn = await widget.food!.importWeekRemind(b.week, b.remind);
      final vitalsIn = await VitalsStore.main.importItems(b.vitals);
      // Round 1 (f3 · S9-11): τι από τους στόχους και τη ζώνη του αντιγράφου ΔΕΝ μπήκε ή συμπληρώθηκε (πριν: σιωπηλά).
      final prefsWereLoaded = widget.store.prefsLoaded;
      final prefsNotes =
          b.prefs.isEmpty || !prefsWereLoaded ? const <String>[] : restoreNotes(widget.store.prefsJson(), b.prefs);
      final prefsOk = b.prefs.isEmpty || await widget.store.restorePrefs(b.prefs);
      final sources = b.sources == null ? null : await widget.store.restoreSourcesWhy(b.sources!);
      // Έλεγχος 20/11 (K6S-01): το ιστορικό ημερών ΜΕΤΑ τις πηγές ύπνου. Πριν έμπαινε πρώτο, και η επαναφορά των πηγών
      // (κανόνας C11: «η νύχτα άλλαξε πηγή → οι παλμοί μέρας ξαναϋπολογίζονται») έσβηνε τους «Παλμούς ξύπνιος» από τις
      // μέρες του Oura που μόλις είχαν μπει από το αντίγραφο· για νύχτες παλιότερες από 45 μέρες δεν ξαναβγαίνουν.
      final hist = await widget.store.importHistoryWhy(b.history, version: b.historyVersion);
      var trainingIn = 0;
      var trainingWritten = true;
      if (b.training != null) {
        await TrainingStore.main.load();
        trainingIn = TrainingStore.main.mergeBackup(b.training!);
        // Round 1 (f3 · S9-5): «μπήκαν» λέγεται μόνο αφού γραφτούν στο κινητό (πριν: πριν από την εγγραφή τους).
        if (trainingIn > 0) trainingWritten = await TrainingStore.main.flush();
      }
      _say([
        'Επαναφορά: ${entriesText(e)} και ${productsText(f)}.',
        if (existing > 0)
          existing == 1 ? '1 εγγραφή υπήρχε ήδη και έμεινε όπως ήταν.' : '$existing εγγραφές υπήρχαν ήδη και έμειναν όπως ήταν.',
        // R7-U4-14 π: με το ουσιαστικό, όπως η γραμμή από κάτω («1 εγγραφή υπήρχε ήδη»)· πριν «3 δεν γράφτηκαν».
        if (failed > 0) '${countText(failed, 'εγγραφή δεν γράφτηκε', 'εγγραφές δεν γράφτηκαν')}· δοκίμασε ξανά.',
        // Round 2 (R2-B-3): «δεν άλλαξαν» μόνο αν δεν άλλαξαν· «μπήκαν αλλά δεν γράφτηκαν» όταν φαίνονται χωρίς να είναι
        // γραμμένες (ίδιο με την κάρτα «Δοκίμασε ξανά» της Σήμερα).
        ...restorePrefsSummary(
            ok: prefsOk, loaded: prefsWereLoaded, unsaved: widget.store.prefsSaveError, notes: prefsNotes),
        if (sources != null) sourcesRestoreText(sources),
        if (trainingIn > 0 && trainingWritten)
          countText(trainingIn, 'προπόνηση μπήκε από το αντίγραφο.', 'προπονήσεις μπήκαν από το αντίγραφο.'),
        if (trainingIn > 0 && !trainingWritten) 'Οι προπονήσεις του αντιγράφου δεν γράφτηκαν στο κινητό· δοκίμασε ξανά.',
        if (b.training != null && TrainingStore.main.mergeProblem != null) TrainingStore.main.mergeProblem!,
        if (dishRes != null && dishRes.$1 > 0)
          countText(dishRes.$1, 'φαγητό μπήκε από το αντίγραφο.', 'φαγητά μπήκαν από το αντίγραφο.'),
        if (b.dishes.isNotEmpty && dishRes == null) 'Τα φαγητά του αντιγράφου δεν γράφτηκαν στο κινητό· δοκίμασε ξανά.',
        if (likesIn) 'Μπήκε και το «Τι μου αρέσει».',
        // 16/11 (έλεγχος): να μη χάνονται σιωπηλά.
        if (vitalsIn > 0) countText(vitalsIn, 'μέτρηση (πίεση, σάκχαρο, καρδιογράφημα) μπήκε.', 'μετρήσεις (πίεση, σάκχαρο, καρδιογράφημα) μπήκαν.'),
        if (vitalsIn < 0) 'Οι μετρήσεις (πίεση, σάκχαρο, καρδιογράφημα) δεν γράφτηκαν στο κινητό· δοκίμασε ξανά.',
        if (marksIn < 0 || unitsIn < 0) 'Τα σημάδια «Τελείωσα για σήμερα» και τα βάρη «Ζύγισα ένα» δεν γράφτηκαν· δοκίμασε ξανά.',
        if (weekIn < 0) 'Το πρόγραμμα εβδομάδας και η ώρα υπενθύμισης δεν γράφτηκαν· δοκίμασε ξανά.',
        ...historyRestoreSummary(hist),
        if (errorsClosed) restoreErrorsClosedText,
      ].join(' '));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFood = widget.food != null;
    return SettingsGroup(key: const ValueKey('settings-data'), children: [
      if (hasFood) ...[
        SettingsRow(
          key: const ValueKey('backup-export'),
          icon: Icons.download_rounded,
          title: 'Εξαγωγή αντιγράφου',
          // Φαγητό, προϊόντα, προπονήσεις και ρυθμίσεις υπάρχουν μόνο σε αυτό το κινητό· η Samsung ξαναδιαβάζεται.
          // Το αρχείο δεν είναι κρυπτογραφημένο: το λέμε (Συμβούλιο 5, Δ6α· κείμενο εγκεκριμένο 13/11).
          // Έλεγχος 17/11 (Κ8-H1): από #132 και το ιστορικό υγείας, και από #124 πίεση/σάκχαρο/καρδιογραφήματα.
          subtitle: 'Ένα αρχείο στις Λήψεις: φαγητό, προϊόντα, προπονήσεις, πίεση/σάκχαρο, ιστορικό υγείας (ύπνος, παλμοί, '
              'ζυγίσεις), ρυθμίσεις. Δεν είναι κλειδωμένο: όποιος το ανοίξει, τα διαβάζει.'
              '\n${lastBackupText(widget.store.lastExport, DateTime.now())}',
          onTap: _busy ? null : _export,
        ),
        // 18/11: πόσο πιάνει το αντίγραφο Google (όριο 25 MB).
        const CloudBackupLine(),
        SettingsRow(
          key: const ValueKey('backup-import'),
          icon: Icons.upload_rounded,
          title: 'Επαναφορά από αντίγραφο',
          onTap: _busy ? null : _import,
        ),
        // Αίτημα χρήστη 12/11: ένα αρχείο με ό,τι γράφτηκε ΚΑΙ ό,τι υπολογίστηκε, για έλεγχο από τον Claude.
        SettingsRow(
          key: const ValueKey('settings-diag'),
          icon: Icons.fact_check_outlined,
          title: 'Αναφορά για έλεγχο',
          subtitle: 'Ό,τι γράφτηκε και ό,τι υπολογίστηκε, σε ένα αρχείο',
          onTap: () => openDiagnostics(context, widget.store, widget.food!),
        ),
      ],
      if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: LinearProgressIndicator()),
      DeleteAllRow(store: widget.store, export: hasFood ? _exportForWipe : null),
    ]);
  }
}


/// Έλεγχος 20/11 (K6S-02, K6S-05): οι γραμμές της σύνοψης της επαναφοράς για το ιστορικό ημερών. Πριν: μόνο «Ν μέρες
/// μπήκαν»· οι μέρες που παραλείφθηκαν επειδή υπήρχαν, και ένα αντίγραφο με άλλους κανόνες ιστορικού, δεν λέγονταν.
List<String> historyRestoreSummary(({int added, int existing, HistoryImportProblem problem}) h) => [
      if (h.added > 0) countText(h.added, 'μέρα ιστορικού μπήκε από το αντίγραφο.', 'μέρες ιστορικού μπήκαν από το αντίγραφο.'),
      if (h.existing > 0)
        countText(h.existing, 'μέρα ιστορικού υπήρχε ήδη στο κινητό και έμεινε όπως είναι.',
            'μέρες ιστορικού υπήρχαν ήδη στο κινητό και έμειναν όπως είναι.'),
      if (h.problem == HistoryImportProblem.otherRules)
        'Το ιστορικό ημερών του αντιγράφου είναι από άλλη έκδοση κανόνων και δεν μπήκε· ξαναδιαβάζεται από το Samsung Health '
            'και το Oura.',
      if (h.problem == HistoryImportProblem.notReady || h.problem == HistoryImportProblem.writeFailed)
        'Το ιστορικό ημερών του αντιγράφου δεν γράφτηκε· δοκίμασε ξανά.',
    ];
