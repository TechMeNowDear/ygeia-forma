import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../training/equipment.dart';
import '../../training/program.dart';
import '../../training/training_store.dart';
import '../../widgets.dart';
import 'training_common.dart';

/// Επικόλληση προγράμματος από τον Claude: προεπισκόπηση πριν την αποθήκευση.
class ProgramPastePage extends StatefulWidget {
  const ProgramPastePage({super.key, required this.training, this.initial});
  final TrainingStore training;

  /// Για δοκιμές: κείμενο αντί για το πρόχειρο.
  final String? initial;

  static Route<void> route(TrainingStore t, {String? text}) =>
      MaterialPageRoute<void>(settings: const RouteSettings(name: 'Επικόλληση προγράμματος'), builder: (_) => ProgramPastePage(training: t, initial: text));

  @override
  State<ProgramPastePage> createState() => _ProgramPastePageState();
}

class _ProgramPastePageState extends State<ProgramPastePage> {
  PasteResult? _r;
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _parse(widget.initial!);
    } else {
      _fromClipboard();
    }
  }

  Future<void> _fromClipboard() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = d?.text ?? '';
    if (text.trim().isEmpty) {
      setState(() => _empty = true);
    } else {
      _parse(text);
    }
  }

  void _parse(String text) => setState(() {
        _empty = false;
        _r = parseProgram(text, exIds());
      });

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final r = _r;
    final body = <Widget>[];
    if (_empty || r == null) {
      body.add(EmptyCard(
        icon: Icons.content_paste_rounded,
        color: c.exercise,
        title: _empty ? 'Το πρόχειρο είναι άδειο' : 'Διαβάζω το πρόχειρο…',
        text: 'Αντίγραφε το πρόγραμμα από τη συζήτηση με τον Claude (όλο το κείμενο) και πάτα «Επικόλληση ξανά».',
      ));
    } else if (!r.ok) {
      body.add(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Δεν μπορεί να αποθηκευτεί', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.bad)),
          const SizedBox(height: 6),
          for (final e in r.errors) Text('• $e', style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text)),
        ]),
      ));
    } else {
      final p = r.program!;
      body.add(AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(p.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
          Text(
            '${p.author == 'claude' ? 'Από τον Claude' : 'Πρόγραμμα'}${p.from == null ? '' : ' · ισχύει από ${p.from!.day}/${p.from!.month}'}',
            style: TextStyle(fontSize: 13.5, color: c.textSecondary),
          ),
          if (p.note != null) ...[const SizedBox(height: 6), Text(p.note!, style: TextStyle(fontSize: 14.5, height: 1.4, color: c.text))],
          const SizedBox(height: 10),
          Row(children: [
            for (var d = 1; d <= 7; d++)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    Text(weekdayShort[d]!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
                    Text(
                      () {
                        final w = p.workout(p.days[d]);
                        return w == null ? '—' : (w.isCardio ? 'Περ.' : w.id);
                      }(),
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  ]),
                ),
              ),
          ]),
        ]),
      ));
      for (final w in p.workouts) {
        body.add(AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${w.name.toUpperCase()} · ~${w.minutes}′', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6, color: c.textSecondary)),
            if (w.isCardio)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${w.cardio!.name} ${w.cardio!.minutes}′${w.cardio!.note == null ? '' : ' · ${w.cardio!.note}'}', style: TextStyle(fontSize: 15, color: c.text)),
              ),
            for (final i in w.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(exName(i.ex), style: TextStyle(fontSize: 15, color: c.text))),
                  Text(
                    '${repsRange(i)} · ${restText(i.rest)}${hasLoad(i.kind) && i.load != null ? ' · ${loadLabel(i.kind, i.load)}' : ''}',
                    style: TextStyle(fontSize: 13.5, color: c.textSecondary),
                  ),
                ]),
              ),
          ]),
        ));
      }
      if (r.warnings.isNotEmpty) {
        body.add(Text(r.warnings.join('\n'), style: TextStyle(fontSize: 13.5, height: 1.4, color: c.textSecondary)));
      }
      final existing = widget.training.programs.any((x) => x.id == p.id);
      body.add(Text(
        existing
            ? 'Αντικαθιστά το τρέχον πρόγραμμα ως νέα έκδοση. Οι παλιές προπονήσεις και τα κιλά τους δεν χάνονται.'
            : 'Γίνεται το ενεργό πρόγραμμα. Οι παλιές προπονήσεις και τα κιλά τους δεν χάνονται.',
        style: TextStyle(fontSize: 13.5, color: c.textSecondary),
      ));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Επικόλληση προγράμματος')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [for (var i = 0; i < body.length; i++) ...[if (i > 0) const SizedBox(height: 12), body[i]]],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _fromClipboard,
                child: const Text('Επικόλληση ξανά'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('paste-save'),
                style: FilledButton.styleFrom(backgroundColor: c.exerciseSolid, foregroundColor: c.onSolid, minimumSize: const Size.fromHeight(50)),
                onPressed: r != null && r.ok
                    ? () {
                        widget.training.saveProgram(r.program!, author: r.program!.author == 'claude' ? 'claude' : 'user');
                        Navigator.of(context).pop();
                      }
                    : null,
                child: const Text('Αποθήκευση προγράμματος', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
