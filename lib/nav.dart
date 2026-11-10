/// Οι τέσσερις προορισμοί της μπάρας. Η σειρά είναι και ο αριθμός τους (Shell.initialIndex).
class Cat {
  static const today = 0;
  static const health = 1;
  static const food = 2;
  static const exercise = 3;
}

/// Καρτέλες μέσα στην Υγεία.
class HealthTab {
  static const sleep = 0;

  /// 7/11: Ετοιμότητα, HRV, θερμοκρασία (από το Oura).
  static const recovery = 1;
  static const heart = 2;
  static const body = 3;
  static const trends = 4;
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
