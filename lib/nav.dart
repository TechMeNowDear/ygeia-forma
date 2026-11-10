/// Οι τέσσερις προορισμοί της μπάρας. Η σειρά είναι και ο αριθμός τους (Shell.initialIndex).
class Cat {
  static const today = 0;
  static const health = 1;
  static const food = 2;
  static const exercise = 3;
}

/// Καρτέλες μέσα στην Υγεία.
/// Σχέδια 9/11 (2β): 4 καρτέλες. Η «Ανάκαμψη» μοιράστηκε στον Ύπνο (δαχτυλίδι Ετοιμότητας και κάρτα «Καρδιά και
/// θερμοκρασία στον ύπνο», κάθε γραμμή ανοίγει τις 30 νύχτες).
class HealthTab {
  static const sleep = 0;
  static const heart = 1;
  static const body = 2;
  static const trends = 3;
}

/// Η Διατροφή (σχέδια 9/11): μία σελίδα, χωρίς υπο-καρτέλες· τα δικά μου ζουν στο «+ Φαγητό» και στο «Τα στοιχεία μου».
class FoodTab {
  static const diary = 0;
}

/// Καρτέλες μέσα στην Άσκηση.
class ExerciseTab {
  /// 8/11: η σημερινή προπόνηση, το πρόγραμμα, το ιστορικό.
  static const train = 0;
  static const move = 1;

  /// 8/11: η βιβλιοθήκη με τις κινούμενες ασκήσεις.
  static const library = 2;
}
