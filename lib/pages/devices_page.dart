import 'package:flutter/material.dart';

import '../oxygen_note.dart' show oxygenAboutText, oxygenRedFlagText;
import '../theme.dart';
import '../widgets.dart';

/// «Τι μετράει κάθε συσκευή» (σχέδια 9/11, 4α): οι εξηγήσεις ζουν σε μία σελίδα. Στις κάρτες μένει μόνο μια ετικέτα
/// (μέτρηση / εκτίμηση / ενδεικτικό) και ένα ⓘ που ανοίγει εδώ, στο σωστό σημείο ([focus]).
/// Τα κείμενα για οξυγόνο και άπνοια έρχονται αυτούσια από το oxygen_note.dart (ένα κείμενο παντού).
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, this.focus});

  /// «oura», «watch», «inbody» ή «oxygen»: η ενότητα που φαίνεται πρώτη.
  final String? focus;

  static Route<void> route({String? focus}) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'Τι μετράει κάθε συσκευή'),
        builder: (_) => DevicesPage(focus: focus),
      );

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

enum _Kind { measured, estimated, indicative }

class _DevicesPageState extends State<DevicesPage> {
  final _keys = {for (final k in ['oura', 'watch', 'inbody', 'oxygen']) k: GlobalKey()};

  @override
  void initState() {
    super.initState();
    final k = _keys[widget.focus];
    if (k != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = k.currentContext;
        if (ctx != null && mounted) Scrollable.ensureVisible(ctx, alignment: 0.05);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    Widget tag(_Kind k) => switch (k) {
          _Kind.measured => const LabelTag('μέτρηση', strong: true),
          _Kind.estimated => const LabelTag('εκτίμηση'),
          _Kind.indicative => const LabelTag('ενδεικτικό', warn: true),
        };
    Widget row(String title, String? sub, _Kind k, {bool line = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: line ? BoxDecoration(border: Border(bottom: BorderSide(color: c.hairline))) : null,
          // Τίτλος αριστερά, ετικέτα δεξιά· με πολύ μεγάλα γράμματα η ετικέτα πάει από κάτω (ποτέ κομμένη).
          child: () {
            final words = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontSize: 15, height: 1.35, color: c.text)),
              if (sub != null) Text(sub, style: TextStyle(fontSize: 13, height: 1.35, color: c.textSecondary)),
            ]);
            if (veryLargeText(context)) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [words, const SizedBox(height: 6), tag(k)]);
            }
            return Row(children: [Expanded(child: words), const SizedBox(width: 10), tag(k)]);
          }(),
        );
    Widget device(String key, IconData icon, String name, String what, List<Widget> rows) => AppCard(
          key: _keys[key],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              IconBadge(icon, c.health, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                  Text(what, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 4),
            ...rows,
          ]),
        );
    // Με μεγάλα γράμματα η ετικέτα πάει πάνω από το κείμενο (ποτέ κομμένη).
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 11.5;
    Widget legend(_Kind k, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: stacked
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  tag(k),
                  const SizedBox(height: 4),
                  Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text)),
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 104, child: Align(alignment: Alignment.centerLeft, child: tag(k))),
                  Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.4, color: c.text))),
                ]),
        );
    final body = TextStyle(fontSize: 15, height: 1.5, color: c.text);

    return Scaffold(
      appBar: AppBar(title: const Text('Τι μετράει κάθε συσκευή')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            // Όλη η σελίδα χτισμένη (όχι ListView): το ⓘ πρέπει να βρίσκει και την τελευταία ενότητα για να πάει εκεί.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Από εδώ έρχονται οι αριθμοί της εφαρμογής. '),
                    const TextSpan(text: 'Καμία συσκευή δεν είναι ιατρική.', style: TextStyle(fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' Στις κάρτες βλέπεις μόνο μια μικρή ετικέτα· η εξήγηση είναι εδώ.'),
                  ]),
                  style: TextStyle(fontSize: 15, height: 1.45, color: c.textSecondary),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Column(children: [
                    legend(_Kind.measured, 'Ο αισθητήρας το μετρά απευθείας. Στις κάρτες δεν γράφεται τίποτα.'),
                    legend(_Kind.estimated, 'Η συσκευή το υπολογίζει από άλλα σήματα. Καλό για τάση, όχι για μία μέρα.'),
                    legend(_Kind.indicative, 'Μέτρηση με γνωστά λάθη στον καρπό ή στο δάχτυλο. Δεν κάνει διάγνωση.'),
                  ]),
                ),
                const SizedBox(height: 12),
                device('oura', Icons.circle_outlined, 'Oura Ring 5', 'δαχτυλίδι · ο ύπνος σου', [
                  row('Ώρες ύπνου', 'από κίνηση και παλμούς', _Kind.estimated),
                  row('Φάσεις ύπνου', null, _Kind.estimated),
                  row('Παλμοί και HRV στον ύπνο', null, _Kind.measured),
                  row('Θερμοκρασία δέρματος', 'απόκλιση από τα συνηθισμένα σου', _Kind.measured),
                  row('Οξυγόνο τη νύχτα, μέσος όρος', null, _Kind.indicative),
                  row('Βαθμολογία ύπνου, Ετοιμότητα', 'βαθμολογία της Oura', _Kind.estimated, line: false),
                ]),
                const SizedBox(height: 12),
                device('watch', Icons.watch_rounded, 'Galaxy Watch Ultra 2', 'ρολόι · μέρα και άσκηση', [
                  row('Βήματα', null, _Kind.measured),
                  row('Παλμοί μέρας και στην άσκηση', 'στα βάρη κατά προσέγγιση', _Kind.measured),
                  row('Απόσταση περπατήματος', 'GPS', _Kind.measured),
                  row('Οξυγόνο τη νύχτα, χαμηλότερη τιμή', null, _Kind.indicative),
                  row('Θερμίδες', 'μεγάλα λάθη, ειδικά στα βάρη· μόνο ως τάση', _Kind.estimated, line: false),
                ]),
                const SizedBox(height: 12),
                device('inbody', Icons.monitor_weight_outlined, 'InBody H40', 'ζυγαριά · σώμα', [
                  row('Βάρος', null, _Kind.measured),
                  row('Λίπος, μύες', 'από ασθενές ρεύμα· ζυγίσου με τις ίδιες συνθήκες', _Kind.estimated),
                  row('Βασικός μεταβολισμός', '±10%', _Kind.estimated, line: false),
                ]),
                const SizedBox(height: 12),
                AppCard(
                  key: _keys['oxygen'],
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      IconBadge(Icons.air_rounded, c.health, size: 36),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Οξυγόνο και άπνοια', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
                    ]),
                    const SizedBox(height: 10),
                    Text(oxygenAboutText, style: body),
                    const SizedBox(height: 12),
                    // Σημάδια κινδύνου: πάντα ορατά, στο κουτί προσοχής.
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.warnBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.warnLine),
                      ),
                      child: Text(oxygenRedFlagText, style: body.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ανοίγει από κάθε «i» (στο σωστό σημείο) και από το «Τα στοιχεία μου».',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
