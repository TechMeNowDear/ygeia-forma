/// Ελληνικά ονόματα για τους τύπους και τα πεδία του Samsung Health.
/// Όλα τα κείμενα μένουν εδώ, ώστε αργότερα να μπουν και αγγλικά.
library;

const typeLabels = <String, String>{
  'sleep': 'Ύπνος',
  'heart_rate': 'Παλμοί',
  'body_composition': 'Σύσταση σώματος (ζυγαριά InBody)',
  'exercise': 'Άσκηση',
  'energy_score': 'Energy Score',
  'blood_oxygen': 'Οξυγόνο αίματος',
  'skin_temperature': 'Θερμοκρασία δέρματος',
  'blood_pressure': 'Πίεση',
  'body_temperature': 'Θερμοκρασία σώματος',
  'blood_glucose': 'Γλυκόζη',
  'water_intake': 'Νερό',
  'nutrition': 'Διατροφή',
  'floors_climbed': 'Όροφοι',
  'sleep_apnea': 'Άπνοια ύπνου',
  'irregular_heart_rhythm': 'Ακανόνιστος καρδιακός ρυθμός',
};

/// Κλειδί: το όνομα του πεδίου με πεζά και χωρίς σύμβολα.
const fieldLabels = <String, String>{
  // Σύσταση σώματος
  'weight': 'Βάρος (kg)',
  'height': 'Ύψος (cm)',
  'bodyfat': 'Λίπος (%)',
  'bodyfatmass': 'Μάζα λίπους (kg)',
  'skeletalmuscle': 'Σκελετικοί μύες (%)',
  'skeletalmusclemass': 'Σκελετικοί μύες (kg)',
  'musclemass': 'Μυϊκή μάζα',
  'basalmetabolicrate': 'Βασικός μεταβολισμός (kcal)',
  'fatfree': 'Άλιπη μάζα (%)',
  'fatfreemass': 'Άλιπη μάζα (kg)',
  'totalbodywater': 'Νερό σώματος (L)',
  'bodymassindex': 'Δείκτης μάζας σώματος',
  // Ύπνος
  'duration': 'Διάρκεια',
  'sessions': 'Περίοδοι και φάσεις',
  'sleepscore': 'Βαθμολογία ύπνου',
  // Παλμοί, οξυγόνο, θερμοκρασία
  'heartrate': 'Παλμοί (bpm)',
  'minheartrate': 'Ελάχιστοι παλμοί',
  'maxheartrate': 'Μέγιστοι παλμοί',
  'seriesdata': 'Αναλυτικές μετρήσεις',
  'oxygensaturation': 'Οξυγόνο (%)',
  'minoxygensaturation': 'Ελάχιστο οξυγόνο (%)',
  'maxoxygensaturation': 'Μέγιστο οξυγόνο (%)',
  'skintemperature': 'Θερμοκρασία δέρματος (°C)',
  'minskintemperature': 'Ελάχιστη θερμοκρασία (°C)',
  'maxskintemperature': 'Μέγιστη θερμοκρασία (°C)',
  'bodytemperature': 'Θερμοκρασία (°C)',
  'energyscore': 'Energy Score',
  // Άσκηση
  'exercisetype': 'Είδος άσκησης',
  'customtitle': 'Τίτλος',
  // Πίεση
  'systolic': 'Συστολική',
  'diastolic': 'Διαστολική',
  'mean': 'Μέση',
  'pulserate': 'Σφυγμός',
  'medicationtaken': 'Πήρα φάρμακο',
  // Νερό και διατροφή
  'amount': 'Ποσότητα (ml)',
  'calories': 'Θερμίδες',
  'protein': 'Πρωτεΐνη (g)',
  'carbohydrate': 'Υδατάνθρακες (g)',
  'totalfat': 'Λιπαρά (g)',
  'dietaryfiber': 'Ίνες (g)',
  'sugar': 'Σάκχαρα (g)',
  'mealtype': 'Γεύμα',
  'title': 'Όνομα',
  'floor': 'Όροφοι',
  'detectedsign': 'Ένδειξη',
  'status': 'Κατάσταση',
};

String fieldLabel(String raw) {
  final last = raw.contains('.') ? raw.substring(raw.lastIndexOf('.') + 1) : raw;
  final key = last.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  return fieldLabels[key] ?? raw;
}

/// Γνωστές εφαρμογές που γράφουν στο Samsung Health.
String appLabel(String appId) {
  if (appId.isEmpty) return 'Άγνωστη πηγή';
  if (appId == 'com.sec.android.app.shealth') return 'Samsung Health (κινητό)';
  if (appId == 'com.samsung.android.wear.shealth') return 'Samsung Health (ρολόι)';
  if (appId.toLowerCase().contains('inbody')) return 'InBody';
  return appId;
}

/// Τι σημαίνει κάθε σφάλμα και τι να κάνω, σε απλά ελληνικά.
String errorText(String kind) {
  switch (kind) {
    case 'not_installed':
      return 'Δεν βρέθηκε το Samsung Health σε αυτό το κινητό.';
    case 'old_version':
      return 'Το Samsung Health χρειάζεται ενημέρωση από το Galaxy Store ή το Play.';
    case 'disabled':
      return 'Το Samsung Health είναι απενεργοποιημένο. Ενεργοποίησέ το από τις Ρυθμίσεις › Εφαρμογές.';
    case 'not_initialized':
      return 'Άνοιξε μία φορά το Samsung Health, ολοκλήρωσε την αρχική ρύθμιση και ξαναδοκίμασε.';
    case 'no_permission':
      return 'Δεν έχει δοθεί άδεια. Πάτα «Σύνδεση με Samsung Health».';
    case 'not_allowed':
      return 'Το Samsung Health δεν επιτρέπει την ανάγνωση. Έλεγξε ότι είναι ανοιχτό το «Developer Mode for Data Read» '
          '(Samsung Health › Ρυθμίσεις › Σχετικά › 10 πατήματα στην έκδοση).';
    case 'connection':
      return 'Δεν έγινε σύνδεση με το Samsung Health. Δοκίμασε ξανά σε λίγο.';
    case 'not_android':
      return 'Αυτή η οθόνη δουλεύει μόνο στο κινητό.';
    default:
      return 'Κάτι πήγε στραβά.';
  }
}
