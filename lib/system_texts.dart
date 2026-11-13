import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';

/// Round 7 (R7-U4-7): τα κείμενα που γράφει μόνο του το Flutter, στα ελληνικά. Πριν, το παρατεταμένο πάτημα σε πεδίο
/// έδειχνε «Cut · Copy · Paste · Select all», η σελίδα αδειών «Licenses», και το TalkBack διάβαζε «Back», «Dismiss»,
/// «Bottom Sheet», «Refresh».
///
/// Χωρίς το `flutter_localizations` (απόφαση 13/11): φέρνει το πακέτο `intl` από το pub.dev (νέα εξάρτηση, αντίθετα με το
/// «μηδέν εξαρτήσεις») και τα κείμενα ~80 γλωσσών μέσα στο APK (εκτίμηση: περίπου 1 MB ανά αρχιτεκτονική, δεν μετρήθηκε
/// εδώ). Εδώ: μόνο όσα δείχνει η εφαρμογή, λίγα KB. Ό,τι δεν μεταφράζεται εδώ μένει όπως στο Flutter (αγγλικά), όπως πριν.
///
/// Η γλώσσα της εφαρμογής ΔΕΝ αλλάζει (μένει η προεπιλογή του Flutter): με `locale: el` κάθε άλλο είδος κειμένων του
/// Flutter (Widgets, Cupertino) θα ήθελε κι αυτό δικό του ελληνικό «delegate», αλλιώς σφάλμα. Αυτό εδώ αντικαθιστά μόνο
/// τα κείμενα της Material, σε όποια γλώσσα κι αν είναι το κινητό.
class GreekMaterialLocalizations extends DefaultMaterialLocalizations {
  const GreekMaterialLocalizations();

  // Μενού επιλογής κειμένου (παρατεταμένο πάτημα σε πεδίο).
  @override
  String get cutButtonLabel => 'Αποκοπή';
  @override
  String get copyButtonLabel => 'Αντιγραφή';
  @override
  String get pasteButtonLabel => 'Επικόλληση';
  @override
  String get selectAllButtonLabel => 'Επιλογή όλων';
  @override
  String get lookUpButtonLabel => 'Αναζήτηση';
  @override
  String get searchWebButtonLabel => 'Αναζήτηση στο διαδίκτυο';
  @override
  String get shareButtonLabel => 'Κοινοποίηση';
  @override
  String get scanTextButtonLabel => 'Σάρωση κειμένου';

  // Κουμπιά με εικονίδιο (αυτά διαβάζει το TalkBack).
  @override
  String get backButtonTooltip => 'Πίσω';
  @override
  String get closeButtonTooltip => 'Κλείσιμο';
  @override
  String get deleteButtonTooltip => 'Διαγραφή';
  @override
  String get clearButtonTooltip => 'Καθαρισμός κειμένου';
  @override
  String get moreButtonTooltip => 'Περισσότερα';
  @override
  String get showMenuTooltip => 'Εμφάνιση μενού';
  @override
  String get openAppDrawerTooltip => 'Άνοιγμα μενού';
  @override
  String get cancelButtonLabel => 'Ακύρωση';
  @override
  String get closeButtonLabel => 'Κλείσιμο';
  @override
  String get continueButtonLabel => 'Συνέχεια';

  // Φύλλα, μενού, παράθυρα, ανανέωση (TalkBack).
  @override
  String get modalBarrierDismissLabel => 'Κλείσιμο';
  @override
  String get menuDismissLabel => 'Κλείσιμο μενού';
  @override
  String get bottomSheetLabel => 'Φύλλο στο κάτω μέρος';
  @override
  String get scrimLabel => 'Σκούρο φόντο';
  @override
  String scrimOnTapHint(String modalRouteContentName) => 'κλείσιμο: $modalRouteContentName';
  @override
  String get popupMenuLabel => 'Μενού';
  @override
  String get dialogLabel => 'Παράθυρο';
  @override
  String get alertDialogLabel => 'Ειδοποίηση';
  @override
  String get drawerLabel => 'Μενού';
  @override
  String get searchFieldLabel => 'Αναζήτηση';
  @override
  String get refreshIndicatorSemanticLabel => 'Ανανέωση';

  // Πεδία με όριο χαρακτήρων (TalkBack).
  @override
  String remainingTextFieldCharacterCount(int remaining) => switch (remaining) {
        0 => 'Δεν απομένουν χαρακτήρες',
        1 => 'Απομένει 1 χαρακτήρας',
        _ => 'Απομένουν $remaining χαρακτήρες',
      };

  // Λίστες που ανοίγουν και κλείνουν (π.χ. «Πεδία» στο «Τι φτάνει»). Ίδια σημασία με τα αγγλικά του Flutter
  // (expandedHint = «Collapsed», collapsedHint = «Expanded»). Τα «…TapHint» (και το scrimOnTapHint) τα λέει το TalkBack
  // μετά το «Πατήστε δύο φορές για», γι' αυτό με μικρό πρώτο γράμμα.
  @override
  String get expandedIconTapHint => 'κλείσιμο';
  @override
  String get collapsedIconTapHint => 'άνοιγμα';
  @override
  String get expansionTileExpandedHint => 'πάτα δύο φορές για να κλείσει';
  @override
  String get expansionTileCollapsedHint => 'πάτα δύο φορές για να ανοίξει';
  @override
  String get expansionTileExpandedTapHint => 'κλείσιμο';
  @override
  String get expansionTileCollapsedTapHint => 'άνοιγμα για περισσότερα';
  @override
  String get expandedHint => 'Έκλεισε';
  @override
  String get collapsedHint => 'Άνοιξε';

  // Ρυθμίσεις › Άδειες λογισμικού (σελίδα του Flutter).
  @override
  String get licensesPageTitle => 'Άδειες λογισμικού';
  @override
  String get viewLicensesButtonLabel => 'Άδειες λογισμικού';
  @override
  String licensesPackageDetailText(int licenseCount) => switch (licenseCount) {
        0 => 'Καμία άδεια',
        1 => '1 άδεια',
        _ => '$licenseCount άδειες',
      };
}

class _GreekMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _GreekMaterialDelegate();

  // Κάθε γλώσσα του κινητού: η εφαρμογή είναι μόνο στα ελληνικά.
  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(const GreekMaterialLocalizations());

  @override
  bool shouldReload(_GreekMaterialDelegate old) => false;
}

/// Για το `localizationsDelegates` ΚΑΘΕ MaterialApp της εφαρμογής (κύρια, ρύθμιση widget, «Η διαγραφή δεν τελείωσε»).
/// Μπαίνει πριν από τα αγγλικά του Flutter, άρα κερδίζει.
const greekSystemTexts = <LocalizationsDelegate<dynamic>>[_GreekMaterialDelegate()];
