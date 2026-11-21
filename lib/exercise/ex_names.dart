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
  'dips': 'Βυθίσεις',
  'db_curl': 'Κάμψεις δικεφάλων με αλτήρες',
  'incline_curl': 'Κάμψεις σε κλίση',
  'hammer_curl': 'Κάμψεις σφυριά',
  'lying_ext': 'Τρικέφαλοι ξαπλωτός με αλτήρες',
  'overhead_ext': 'Έκταση πάνω από το κεφάλι',
  'band_pushdown': 'Πιέσεις τρικεφάλων με λάστιχο',
  'crunch': 'Κοιλιακοί στο πάτωμα',
  'reverse_crunch': 'Ανάποδοι κοιλιακοί στον πάγκο',
  'ab_wheel': 'Ρόδα κοιλιακών από τα γόνατα',
  'pallof': 'Πίεση κορμού με λάστιχο',
  'db_row': 'Κωπηλασία με αλτήρα',
  'band_pulldown': 'Έλξεις τροχαλίας με λάστιχο',
  'assisted_pullup': 'Έλξεις με λάστιχο (βοήθεια)',
  'face_pull': 'Έλξη στο πρόσωπο με λάστιχο',
  'band_er': 'Εξωτερική στροφή με λάστιχο',
  'shoulder_press': 'Πίεση ώμων με αλτήρες, καθιστός',
  'lateral_raise': 'Πλάγιες ανυψώσεις',
  'goblet': 'Κάθισμα με βάρος στο στήθος',
  'rdl': 'Ρουμανική άρση θανάτου',
  'split_squat': 'Στατικές προβολές με αλτήρες',
  'leg_curl': 'Κάμψεις ποδιών στον πάγκο',
  'leg_ext': 'Εκτάσεις ποδιών',
  'hip_thrust': 'Ανύψωση λεκάνης στον πάγκο',
};

/// Α24 (απόφαση χρήστη 21/11): το σύντομο αγγλικό όνομα των ασκήσεων που οι περισσότεροι ξέρουν με αυτό· φαίνεται μικρό
/// κάτω από το ελληνικό. Ίδιο με το `enName` της βιβλιοθήκης (η ίδια δοκιμή τα συγκρίνει ένα προς ένα).
const exEnNamesById = <String, String>{
  'dips': 'Dips',
  'hammer_curl': 'Hammer curl',
  'band_pushdown': 'Band pushdown',
  'crunch': 'Crunch',
  'reverse_crunch': 'Reverse crunch',
  'pallof': 'Pallof press',
  'face_pull': 'Face pull',
  'goblet': 'Goblet squat',
  'rdl': 'Romanian deadlift',
  'split_squat': 'Split squat',
  'leg_curl': 'Leg curl',
  'leg_ext': 'Leg extension',
  'hip_thrust': 'Hip thrust',
};
