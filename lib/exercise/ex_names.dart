/// Τα ελληνικά ονόματα των ασκήσεων (id → όνομα), για την κάρτα «Άσκηση σήμερα» της Σήμερα χωρίς να φορτωθεί όλη η
/// βιβλιοθήκη (assets/exercises/exercises.json, ~450 KB) με το άνοιγμα της εφαρμογής. Βγαίνει από το ίδιο αρχείο·
/// η δοκιμή test/premium_test.dart ελέγχει ότι ταιριάζουν ένα προς ένα.
library;

const exNamesById = <String, String>{
  'db_press': 'Πιεστικό με αλτήρες',
  'incline_press': 'Πιεστικό σε κλίση με αλτήρες',
  'pushup_handles': 'Κάμψεις με λαβές',
  'pushup_bench': 'Κάμψεις με τα χέρια στον πάγκο',
  'band_fly': 'Ανοίγματα με λάστιχο',
  'dips': 'Βυθίσεις (dips)',
  'db_curl': 'Κάμψεις δικεφάλων με αλτήρες',
  'incline_curl': 'Κάμψεις σε κλίση',
  'hammer_curl': 'Κάμψεις σφυριά (hammer)',
  'lying_ext': 'Τρικέφαλοι ξαπλωτός με αλτήρες',
  'overhead_ext': 'Έκταση πάνω από το κεφάλι',
  'band_pushdown': 'Pushdown με λάστιχο',
  'crunch': 'Crunch (κοιλιακοί στο πάτωμα)',
  'reverse_crunch': 'Ανάποδο crunch στον πάγκο',
  'ab_wheel': 'Ρόδα κοιλιακών από τα γόνατα',
  'pallof': 'Pallof press',
  'db_row': 'Κωπηλασία με αλτήρα',
  'band_pulldown': 'Έλξεις τροχαλίας με λάστιχο',
  'assisted_pullup': 'Έλξεις με λάστιχο (βοήθεια)',
  'face_pull': 'Face pull με λάστιχο',
  'band_er': 'Εξωτερική στροφή με λάστιχο',
  'shoulder_press': 'Πίεση ώμων με αλτήρες, καθιστός',
  'lateral_raise': 'Πλάγιες ανυψώσεις',
  'goblet': 'Goblet squat',
  'rdl': 'Romanian deadlift',
  'split_squat': 'Split squat με αλτήρες',
  'leg_curl': 'Leg curl στον πάγκο',
  'leg_ext': 'Leg extension',
  'hip_thrust': 'Hip thrust στον πάγκο',
};
