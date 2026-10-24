import 'package:flutter/material.dart';

import 'theme.dart';
import 'ti_ftanei.dart';

void main() {
  runApp(const YgeiaFormaApp());
}

class YgeiaFormaApp extends StatelessWidget {
  const YgeiaFormaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Υγεία & Φόρμα',
      debugShowCheckedModeBanner: false,
      // Ανοιχτό ή σκοτεινό, όπως είναι ρυθμισμένο το κινητό.
      themeMode: ThemeMode.system,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const TiFtaneiScreen(),
    );
  }
}
