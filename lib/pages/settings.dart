import 'package:flutter/material.dart';

import '../data.dart';
import '../format.dart';
import '../theme.dart';
import '../ti_ftanei.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final HealthStore store;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppCard(
                        padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Τι βλέπω στο «Σήμερα»'),
                            const SizedBox(height: 4),
                            Text(
                              'Τα δεδομένα διαβάζονται όλα· εδώ διαλέγεις μόνο τι εμφανίζεται.',
                              style: TextStyle(color: c.textSecondary, fontSize: 13),
                            ),
                            for (final card in todayCards)
                              SwitchListTile(
                                contentPadding: const EdgeInsets.only(right: 4),
                                title: Text(card.label),
                                value: store.prefs.show(card.key),
                                onChanged: (on) => store.setCard(card.key, on),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SectionLabel('Samsung Health'),
                            const SizedBox(height: 6),
                            InfoRow('Άδειες', d == null ? '—' : '${d.granted} από ${d.total}'),
                            InfoRow('Τελευταία ανάγνωση', d == null ? '—' : '${relativeDay(d.readAt, DateTime.now())} ${hm(d.readAt)}'),
                            const SizedBox(height: 10),
                            OutlinedButton(
                              onPressed: () => store.refresh(askPermissions: true),
                              child: const Text('Άδειες Samsung Health'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => Scaffold(
                                    appBar: AppBar(title: const Text('Έλεγχος δεδομένων')),
                                    body: const TiFtaneiScreen(),
                                  ),
                                ),
                              ),
                              child: const Text('Έλεγχος δεδομένων («Τι φτάνει»)'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Υγεία & Φόρμα · προσωπική έκδοση. Η εφαρμογή διαβάζει δεδομένα μόνο όταν την ανοίγεις.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
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
