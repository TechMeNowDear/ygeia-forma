// «AI για το φαγητό» (Ρυθμίσεις, 19/11, βαθύς έλεγχος 19/11): σύνδεση με τη γέφυρα στο Supabase, βήμα-βήμα, και δοκιμή.
import 'package:flutter/material.dart';

import '../ai/ai_bridge.dart';
import '../history.dart' show dateKey;
import '../oura/oura_store.dart' show ChannelVault;
import '../theme.dart';
import '../widgets.dart';
import 'privacy_page.dart' show SettingsGroup, SettingsRow, SettingsSection, copySensitive;

/// Η γέφυρα της εφαρμογής (κρυπτογραφημένη αποθήκευση του κινητού).
AiBridge get mainAiBridge => AiBridge.shared ??= AiBridge(const ChannelVault());

/// Τι στέλνεται στο AI (το ίδιο λέει και η πολιτική απορρήτου).
const aiSendsText = 'Στέλνονται μόνο: τα τρόφιμα που σου αρέσουν και τα βασικά κουζίνας (ονόματα), τα φαγητά της '
    'βιβλιοθήκης σου (και όσα δεν σου άρεσαν, για να μην ξαναμπούν), τα φαγητά που μένουν στο πρόγραμμα, οι συσκευές και τα '
    'σκεύη της κουζίνας σου, οι σημειώσεις στο «Τι μου αρέσει», οι μέρες γραφείου, πόσα όσπρια και ψάρι θέλεις την '
    'εβδομάδα, οι θερμίδες ανά γεύμα σε στρογγυλά νούμερα, τα όρια διατροφής της μέρας (κορεσμένα, αλάτι, ίνες, πρωτεΐνη) '
    'με τα κορεσμένα και το αλάτι των τροφίμων από τη βάση και, όταν αλλάζεις ένα γεύμα, η αιτία και τα νούμερα εκείνης της '
    'μερίδας. Ποτέ ζυγίσεις, ύπνος, παλμοί, εξετάσεις, φάρμακα ή δεδομένα του Oura.';

/// Βήματα εγκατάστασης (μία φορά), για τη σελίδα.
const aiSetupSteps = [
  ('Claude Console', 'Στο console.anthropic.com, με το ίδιο email: φτιάξε ένα Workspace μόνο για αυτό (π.χ. «ygeia») και '
      'βάλε του όριο δαπάνης (Limits). Μετά API Keys › Create Key μέσα σε αυτό το Workspace. Μην το στείλεις σε κανέναν.'),
  ('Supabase project', 'Στο supabase.com: New project, περιοχή Central EU (Frankfurt). Το Project ID είναι στο Project '
      'Settings › General.'),
  ('Η function «ai-food»', 'Edge Functions › Deploy a new function › Via Editor, όνομα ακριβώς ai-food, επικόλληση του '
      'κώδικα από το αρχείο supabase/functions/ai-food/index.ts του repo, Deploy. Μετά, στα Details της function, κλείσε το '
      '«Verify JWT» (ο έλεγχος γίνεται με το κλειδί της εφαρμογής).'),
  ('Secrets', 'Edge Functions › Secrets: πρόσθεσε ANTHROPIC_API_KEY (το κλειδί του Claude Console) και APP_TOKEN (το κλειδί '
      'της εφαρμογής από το βήμα 1 εδώ). Άνοιξε το supabase.com στο ίδιο κινητό για να το επικολλήσεις.'),
];

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key, this.bridge, this.clock});
  final AiBridge? bridge;
  final DateTime Function()? clock;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late final AiBridge b = widget.bridge ?? mainAiBridge;
  final _id = TextEditingController();
  bool _loading = true;
  bool _vaultError = false;
  bool _busy = false;
  bool _showToken = false;
  String? _test;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    b.load().then((ok) {
      if (!mounted) return;
      final u = b.url;
      _id.text = u == null ? '' : u.host.split('.').first;
      setState(() {
        _loading = false;
        _vaultError = !ok;
      });
    });
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  void _say(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), persist: false));

  Future<void> _makeToken({bool fresh = false}) async {
    if (fresh) {
      final ok = await showDialog<bool>(
        context: context,
        routeSettings: const RouteSettings(name: 'AI νέο κλειδί'),
        builder: (ctx) => AlertDialog(
          title: const Text('Νέο κλειδί;'),
          content: const Text('Το παλιό σταματά να δουλεύει. Θα χρειαστεί να βάλεις το νέο στο Supabase (APP_TOKEN).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Νέο κλειδί')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final t = fresh ? await b.resetToken() : await b.ensureToken();
    if (!mounted) return;
    if (t == null) {
      _say('Δεν αποθηκεύτηκε το κλειδί (η ασφαλής αποθήκευση δεν απάντησε). Δοκίμασε ξανά.');
      return;
    }
    setState(() => _test = null);
  }

  /// Αντιγραφή ως «ευαίσθητο» (X-7): δεν φαίνεται στην προεπισκόπηση του Android και δεν μένει στο ιστορικό πρόχειρου.
  Future<void> _copy() async {
    final t = b.token;
    if (t == null) return;
    await copySensitive(t);
    if (mounted) _say('Αντιγράφηκε (κρυφά). Επικόλλησέ το στο Supabase, στο ίδιο κινητό.');
  }

  Future<bool> _saveId({bool quiet = false}) async {
    final ok = await b.setUrl(_id.text);
    if (!mounted) return ok;
    if (!ok) {
      _say('Δεν είναι Project ID του Supabase: 20 μικρά γράμματα και αριθμοί, ή το «Project URL» (https://….supabase.co).');
      return false;
    }
    FocusScope.of(context).unfocus();
    _id.text = b.url!.host.split('.').first;
    setState(() => _test = null);
    if (!quiet) _say('Αποθηκεύτηκε.');
    return true;
  }

  Future<void> _try() async {
    // Ό,τι γράφτηκε στο πεδίο αποθηκεύεται πρώτα (U-12).
    if (_id.text.trim().isNotEmpty && bridgeUrl(_id.text) != b.url && !await _saveId(quiet: true)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _test = null;
    });
    try {
      final r = await b.call(const AiAsk(
        model: aiModelRecipe,
        system: 'Είσαι δοκιμή σύνδεσης. Απάντησε μόνο με τη λέξη ΟΚ.',
        messages: [('user', 'Δοκιμή')],
        maxTokens: 50,
      ));
      if (r.text != null) await b.markOk(dateKey((widget.clock ?? DateTime.now)()));
      if (!mounted) return;
      setState(() {
        _testOk = r.text != null;
        _test = r.text != null ? 'Η σύνδεση δουλεύει.' : aiErrorText(r.fail ?? AiFail.bad);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      routeSettings: const RouteSettings(name: 'AI αποσύνδεση'),
      builder: (ctx) => AlertDialog(
        title: const Text('Αποσύνδεση;'),
        content: const Text('Σβήνονται από το κινητό η διεύθυνση και το κλειδί. Τα προγράμματα και τα φαγητά σου μένουν. Η '
            'function και τα secrets μένουν στο Supabase σου (σβήνονται από εκεί).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Άκυρο')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Αποσύνδεση')),
        ],
      ),
    );
    if (ok != true) return;
    await b.disconnect();
    if (!mounted) return;
    setState(() {
      _id.clear();
      _test = null;
      _showToken = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    final token = b.token;
    final hasUrl = b.url != null;
    final status = _vaultError
        ? 'Η ασφαλής αποθήκευση του κινητού δεν απάντησε. Βγες και ξαναμπές σε λίγο.'
        : !b.ready
            ? 'Δεν έχει συνδεθεί. Η σύνδεση γίνεται μία φορά, με τα βήματα παρακάτω.'
            : b.okDay == null
                ? 'Αποθηκεύτηκαν διεύθυνση και κλειδί. Πάτα «Δοκιμή σύνδεσης».'
                : 'Συνδεδεμένο ✓ (δοκιμή ${b.okDay!.substring(8)}/${int.parse(b.okDay!.substring(5, 7))}). Στο «Πρόγραμμα '
                    'εβδομάδας» πάτα «Φτιάξ’ το με AI».';
    Widget step(String n, String title, String text, List<Widget> body) => AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(radius: 13, backgroundColor: c.primary, child: Text(n, style: TextStyle(color: c.onPrimary, fontSize: 13, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            ]),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 12),
            ...body,
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('AI για το φαγητό'), backgroundColor: c.background, surfaceTintColor: Colors.transparent),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(status,
                          key: const ValueKey('ai-status'),
                          style: TextStyle(
                              fontSize: 15, height: 1.4, fontWeight: FontWeight.w600, color: b.okDay != null && b.ready ? c.good : c.text)),
                      const SizedBox(height: 6),
                      Text(
                        'Το AI φτιάχνει το πρόγραμμα της εβδομάδας μόνο από ό,τι σου αρέσει και αλλάζει ένα γεύμα με ανάλογο. Οι '
                        'θερμίδες και τα θρεπτικά μετριούνται πάντα από τη βάση της εφαρμογής.',
                        style: TextStyle(fontSize: 14, height: 1.4, color: c.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: ExpansionTile(
                          key: const ValueKey('ai-setup-guide'),
                          tilePadding: EdgeInsets.zero,
                          initiallyExpanded: !b.ready,
                          title: Text('Πρώτη φορά: τι γίνεται στο Claude Console και στο Supabase',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                          children: [
                            for (var k = 0; k < aiSetupSteps.length; k++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: '${String.fromCharCode(0x0391 + k)}. ${aiSetupSteps[k].$1}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    TextSpan(text: aiSetupSteps[k].$2),
                                  ]),
                                  style: TextStyle(fontSize: 14, height: 1.45, color: c.text),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      step('1', 'Κλειδί της εφαρμογής',
                          'Το φτιάχνει το κινητό. Το βάζεις στο Supabase ως secret «APP_TOKEN», ώστε η γέφυρα να δέχεται μόνο εσένα. Μην το στείλεις σε κανέναν.', [
                        if (token == null)
                          FilledButton.icon(
                            key: const ValueKey('ai-make-token'),
                            onPressed: _vaultError ? null : _makeToken,
                            icon: const Icon(Icons.key_rounded),
                            label: const Text('Φτιάξε κλειδί'),
                          )
                        else ...[
                          Text(
                            _showToken ? token : '${token.substring(0, 4)}••••••••••••${token.substring(token.length - 4)}',
                            key: const ValueKey('ai-token'),
                            style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: c.text),
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.tonalIcon(
                              key: const ValueKey('ai-copy-token'),
                              onPressed: _copy,
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Αντιγραφή'),
                            ),
                            TextButton(
                              key: const ValueKey('ai-show-token'),
                              onPressed: () => setState(() => _showToken = !_showToken),
                              child: Text(_showToken ? 'Κρύψ’ το' : 'Δείξ’ το'),
                            ),
                          ]),
                        ],
                      ]),
                      const SizedBox(height: 12),
                      step('2', 'Project ID του Supabase',
                          'Στο supabase.com, στο project της γέφυρας: Project Settings › General › Project ID (ή επικόλλησε το Project URL).', [
                        TextField(
                          key: const ValueKey('ai-project-id'),
                          controller: _id,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(hintText: 'π.χ. abcdefghij0123456789', border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _saveId(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(key: const ValueKey('ai-save-id'), onPressed: () => _saveId(), child: const Text('Αποθήκευση')),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      step('3', 'Δοκιμή', 'Ελέγχει ότι η γέφυρα και το Claude API απαντούν (μία πολύ μικρή ερώτηση).', [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const ValueKey('ai-test'),
                            onPressed: token != null && (hasUrl || _id.text.trim().isNotEmpty) && !_busy ? _try : null,
                            icon: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_tethering_rounded),
                            label: const Text('Δοκιμή σύνδεσης'),
                          ),
                        ),
                        if (token == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Πρώτα το βήμα 1.', style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                          ),
                        if (_test != null) ...[
                          const SizedBox(height: 10),
                          Text(_test!,
                              key: const ValueKey('ai-test-result'),
                              style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: _testOk ? c.good : c.bad)),
                        ],
                      ]),
                      const SettingsSection('Τι στέλνεται'),
                      AppCard(child: Text(aiSendsText, style: TextStyle(fontSize: 14, height: 1.45, color: c.textSecondary))),
                      if (token != null || hasUrl) ...[
                        const SettingsSection('Για προχωρημένους'),
                        SettingsGroup(children: [
                          SettingsRow(
                            icon: Icons.autorenew_rounded,
                            title: 'Νέο κλειδί',
                            subtitle: 'Αν το παλιό το είδε κάποιος άλλος, ή σε νέο κινητό.',
                            onTap: () => _makeToken(fresh: true),
                          ),
                          SettingsRow(
                            key: const ValueKey('ai-disconnect'),
                            icon: Icons.link_off_rounded,
                            title: 'Αποσύνδεση',
                            danger: true,
                            onTap: _disconnect,
                          ),
                        ]),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}
