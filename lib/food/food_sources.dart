/// Οι πηγές των τιμών διατροφής, με έκδοση, ημερομηνία και άδεια, όπως ζητούν οι άδειες (έλεγχος 9/11, Μ5):
/// - CIQUAL (Licence Ouverte / Etalab 2.0): αναφορά της πηγής ΚΑΙ της ημερομηνίας της τελευταίας ενημέρωσης.
/// - USDA FoodData Central (CC0): ζητά (όχι υποχρεωτικά) να αναφέρεται.
/// - Open Food Facts (ODbL): αναφορά, και share-alike αν η βάση μοιραστεί.
/// Ένα σημείο για όλες τις οθόνες (λεπτομέρειες τροφίμου, «Πηγές και άδειες»), ώστε να μη διαφωνούν.
library;

class FoodSourceInfo {
  const FoodSourceInfo({required this.title, required this.version, required this.licence, required this.detail, this.link});
  final String title;
  final String version;
  final String licence;

  /// Τι κάναμε εμείς στα δεδομένα (η άδεια θέλει να φαίνεται ότι προσαρμόστηκαν).
  final String detail;
  final String? link;
}

const ciqualInfo = FoodSourceInfo(
  title: 'CIQUAL 2025 (ANSES)',
  version: 'Πίνακας Ciqual 2025, ενημέρωση 19/11/2025 · doi:10.57745/RDMHWY',
  licence: 'Licence Ouverte / Etalab 2.0',
  detail: 'Ελληνικά ονόματα από εμάς. Αλάτι = νάτριο × 2,5 (κανόνας ΕΕ). Πρωτεΐνη N × 6,25, όπως στις ετικέτες της ΕΕ.',
  link: 'https://ciqual.anses.fr',
);

const usdaInfo = FoodSourceInfo(
  title: 'USDA FoodData Central',
  version: 'SR Legacy (2018) και Foundation Foods (04/2026)',
  licence: 'Δημόσιο αγαθό (CC0 1.0)',
  detail: 'Ελληνικά ονόματα από εμάς. Υδατάνθρακες χωρίς τις φυτικές ίνες, όπως στις ετικέτες της ΕΕ. '
      'Αλάτι = νάτριο × 2,5.',
  link: 'https://fdc.nal.usda.gov',
);

const offInfo = FoodSourceInfo(
  title: 'Open Food Facts',
  version: 'Ζωντανή βάση, τη στιγμή της σάρωσης',
  licence: 'Open Database License (ODbL)',
  detail: 'Ανοιχτή βάση από εθελοντές. Τα στοιχεία τα ελέγχεις με την ετικέτα πριν αποθηκευτούν και μένουν μόνο '
      'στο κινητό σου.',
  link: 'https://openfoodfacts.org',
);

/// Η πηγή ενός τροφίμου από το πεδίο `source` («CIQUAL 2025», «USDA SR Legacy», «USDA Foundation»,
/// «Open Food Facts», «Ετικέτα»). null για «Ετικέτα».
FoodSourceInfo? sourceInfo(String source) => switch (source) {
      'CIQUAL 2025' => ciqualInfo,
      'Open Food Facts' => offInfo,
      'Ετικέτα' => null,
      _ => usdaInfo,
    };

/// Μία πρόταση για την κάρτα «Πηγή» ενός τροφίμου.
String sourceSentence(String source) {
  final s = sourceInfo(source);
  if (s == null) return 'Από την ετικέτα του προϊόντος, όπως την πέρασες.';
  return '${s.title} · ${s.version} · ${s.licence}. ${s.detail}';
}
