import 'package:flutter/widgets.dart';

/// Άγνωστη διαδρομή → τίποτα καινούργιο: μια σελίδα που κλείνει αμέσως και αφήνει την οθόνη όπως ήταν.
/// Έλεγχος 13/11 (S10-7): εδώ (όχι στο main.dart), ώστε να τη χρησιμοποιεί και το «Η διαγραφή δεν τελείωσε»
/// (WipeUnfinishedApp στο privacy_page.dart), το μόνο MaterialApp της εφαρμογής που δεν είχε καμία. Το main.dart την
/// εξάγει όπως πριν (export 'nav.dart').
Route<void> unknownRoute(RouteSettings settings) => PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'άγνωστη διαδρομή'),
      opaque: false,
      pageBuilder: (context, _, __) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
        return const SizedBox.shrink();
      },
    );

/// Round 9 (R9-U1-3): η πλαϊνή μπάρα (με τις Ρυθμίσεις κάτω) μόνο σε οθόνη φαρδιά ΚΑΙ αρκετά ψηλή· αλλιώς η κάτω μπάρα
/// και το κουμπί Ρυθμίσεων της Σήμερα. Το κλειστό Fold γυρισμένο οριζόντια (≈ 880 × 410 dp) έπαιρνε την πλαϊνή μπάρα, που
/// θέλει ≈ 394 dp ύψος (4 προορισμοί, κενά, κουμπί Ρυθμίσεων· main.dart `_SideBar`) ενώ μένουν ≈ 360–376 dp μετά τη γραμμή
/// κατάστασης και τη γραμμή χειρονομιών: ξεχείλιζε, και οι Ρυθμίσεις έπεφταν κάτω από τη γραμμή χειρονομιών.
bool useSideBar(Size screen) => screen.width >= 600 && screen.height >= 480;

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
