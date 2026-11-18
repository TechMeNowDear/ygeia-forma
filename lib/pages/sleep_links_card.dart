import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data.dart';
import '../food/food_store.dart';
import '../sleep_links.dart';
import '../theme.dart';
import '../widgets.dart';

/// «Τι συνδέεται με τον ύπνο σου» (18/11): στο τέλος της σελίδας Ύπνου. Η λογική και οι πηγές στο [sleepLinks].
class SleepLinksCard extends StatefulWidget {
  const SleepLinksCard({super.key, required this.store, this.food, this.now});
  final HealthStore store;

  /// null = [FoodStore.shared].
  final FoodStore? food;
  final DateTime? now;

  @override
  State<SleepLinksCard> createState() => _SleepLinksCardState();
}

class _SleepLinksCardState extends State<SleepLinksCard> {
  bool _how = false;

  @override
  Widget build(BuildContext context) {
    final food = widget.food ?? FoodStore.shared;
    final listen = food == null ? widget.store : Listenable.merge([widget.store, food]);
    return ListenableBuilder(listenable: listen, builder: (context, _) => _card(context, food));
  }

  Widget _card(BuildContext context, FoodStore? food) {
    final c = Aigaio.of(context);
    final r = sleepLinks(
      history: widget.store.history,
      plan: widget.store.plan,
      today: widget.now ?? DateTime.now(),
      entries: (d) => food?.entriesFor(d) ?? const [],
      mark: (d) => food?.dayMark(d),
    );
    final small = TextStyle(color: c.textSecondary, fontSize: 13, height: 1.35);
    final found = r.found;
    return AppCard(
      key: const ValueKey('sleep-links'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardHeader(
            icon: Icons.insights_rounded,
            title: 'Τι συνδέεται με τον ύπνο σου',
            color: c.sleep,
            subtitle: 'Οι τελευταίες 12 εβδομάδες',
          ),
          const SizedBox(height: 12),
          if (!r.ready) ...[
            Text('Μαζεύω νύχτες: ${math.min(r.nights, sleepLinkMinNights)} από $sleepLinkMinNights.',
                key: const ValueKey('sleep-links-wait'),
                style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: math.min(r.nights, sleepLinkMinNights) / sleepLinkMinNights,
                minHeight: 6,
                color: c.sleep,
                backgroundColor: c.sleep.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text('Το πρώτο αποτέλεσμα θέλει περίπου 4 εβδομάδες με ύπνο από τη συσκευή σου.', style: small),
          ] else if (found.isEmpty)
            Text('Δεν φαίνεται ακόμα καμία σύνδεση. Με περισσότερες νύχτες ο έλεγχος γίνεται πιο ευαίσθητος.',
                key: const ValueKey('sleep-links-none'), style: TextStyle(color: c.text, fontSize: 15, height: 1.35))
          else
            for (final l in found) _row(context, l),
          const SizedBox(height: 10),
          Text('Για το φαγητό μετρούν μόνο οι μέρες με «Τελείωσα για σήμερα». Συνδέεται δεν σημαίνει ότι το ένα φέρνει '
              'το άλλο.', style: small),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('sleep-links-how'),
              onPressed: () => setState(() => _how = !_how),
              child: Text(_how ? 'Λιγότερα' : 'Πώς το βρίσκω'),
            ),
          ),
          if (_how)
            Text(
              'Κάθε νύχτα μπαίνει δίπλα στην προηγούμενη μέρα σου: ώρες από το τελευταίο φαγητό ως τον ύπνο, θερμίδες '
              'βραδινού, βήματα και ώρα ύπνου. Απέναντι: παλμοί ύπνου, HRV και διάρκεια ύπνου. Κάθε ζευγάρι κρίνεται από '
              '$sleepLinkMinNights νύχτες και πάνω. Επειδή είναι 12 ζευγάρια μαζί και οι διαδοχικές νύχτες μοιάζουν, ο '
              'έλεγχος είναι αυστηρός: μια σύνδεση που φαίνεται εδώ είναι σταθερή, όχι τύχη μιας εβδομάδας. Η ώρα του '
              'φαγητού είναι η ώρα που το έγραψες· γράψ\' το όταν το τρως για να βγαίνει σωστά.',
              key: const ValueKey('sleep-links-how-text'),
              style: small,
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, SleepLink l) {
    final c = Aigaio.of(context);
    final (lowLabel, highLabel) = linkGroups(l);
    final (lowValue, highValue) = linkValues(l);
    final title = linkSleepLabel(l.sleep);
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label, style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.3))),
              const SizedBox(width: 12),
              Text(value, style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Padding(
      key: ValueKey('sleep-link-${l.cause.name}-${l.sleep.name}'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${title[0].toUpperCase()}${title.substring(1)} και ${linkCauseLabel(l.cause)}',
              style: TextStyle(color: c.text, fontSize: 15, fontWeight: FontWeight.w700)),
          line(lowLabel, lowValue),
          line(highLabel, highValue),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Μέσος όρος, από ${l.n} νύχτες', style: TextStyle(color: c.textTertiary, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
