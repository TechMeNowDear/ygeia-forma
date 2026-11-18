// «AI για το φαγητό» (Ρυθμίσεις, 19/11): σύνδεση με τη γέφυρα στο Supabase, σε 2 βήματα, και δοκιμή.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_bridge.dart';
import '../oura/oura_store.dart' show ChannelVault;
import '../theme.dart';
import '../widgets.dart';
import 'privacy_page.dart' show SettingsGroup, SettingsRow, SettingsSection;

/// Η γέφυρα της εφαρμογής (κρυπτογραφημένη αποθήκευση του κινητού).
AiBridge get mainAiBridge => AiBridge.shared ??= AiBridge(const ChannelVault());

/// Τι στέλνεται στο AI (ίδιο κείμενο και στην πολιτική απορρήτου).
const aiSendsText = 'Στέλνονται μόνο: τα τρόφιμα που σου αρέσουν και τα βασικά κουζίνας (ονόματα), τα φαγητά της '
    'βιβλιοθήκης σου, οι συσκευές της κουζίνας σου, οι σημειώσεις στο «Τι μου αρέσει» και οι αριθμοί των στόχων φαγητού '
    '(θερμίδες, πρωτεΐνη, κορεσμένα, ίνες, αλάτι). Ποτέ ζυγίσεις, ύπνος, παλμοί, εξετάσεις, φάρμακα ή δεδομένα του Oura.';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key, this.bridge});
  final AiBridge? bridge;

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  late final AiBridge b = widget.bridge ?? mainAiBridge;
  final _id = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _showToken = false;
  String? _test;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    b.load().whenComplete(() {
      if (!mounted) return;
      final u = b.url;
      _id.text = u == null ? '' : u.host.split('.').first;
      setState(() => _loading = false);
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
      _say('Δεν αποθηκεύτηκε το κλειδί. Δοκίμασε ξανά.');
      return;
    }
    setState(() {
      _showToken = true;
      _test = null;
    });
  }

  Future<void> _copy() async {
    final t = b.token;
    if (t == null) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (mounted) _say('Αντιγράφηκε. Επικόλλησέ το στο Supabase και μετά αντίγραψε κάτι άλλο, για να φύγει από το πρόχειρο.');
  }

  Future<void> _saveId() async {
    final ok = await b.setUrl(_id.text);
    if (!mounted) return;
    if (!ok) {
      _say('Δεν είναι Project ID του Supabase: 20 μικρά γράμματα και αριθμοί, π.χ. «abcdefghij0123456789».');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _test = null);
    _say('Αποθηκεύτηκε.');
  }

  Future<void> _try() async {
    setState(() {
      _busy = true;
      _test = null;
    });
    final r = await b.call(const AiAsk(
      model: aiModelRecipe,
      system: 'Είσαι δοκιμή σύνδεσης. Απάντησε μόνο με τη λέξη ΟΚ.',
      messages: [('user', 'Δοκιμή')],
      maxTokens: 10,
    ));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _testOk = r.text != null;
      _test = r.text != null ? 'Η σύνδεση δουλεύει.' : aiErrorText(r.fail ?? AiFail.bad);
    });
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Αποσύνδεση;'),
        content: const Text('Σβήνονται από το κινητό η διεύθυνση και το κλειδί. Τα προγράμματα και τα φαγητά σου μένουν.'),
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
                      Text(
                        b.ready
                            ? 'Συνδεδεμένο. Στο «Πρόγραμμα εβδομάδας» πάτα «Φτιάξ’ το με AI».'
                            : 'Το AI φτιάχνει το πρόγραμμα της εβδομάδας μόνο από ό,τι σου αρέσει και αλλάζει ένα γεύμα με '
                                'ανάλογο. Οι θερμίδες μετριούνται πάντα από τη βάση της εφαρμογής.',
                        key: const ValueKey('ai-status'),
                        style: TextStyle(fontSize: 15, height: 1.4, color: c.text),
                      ),
                      const SizedBox(height: 16),
                      step('1', 'Κλειδί της εφαρμογής',
                          'Το φτιάχνει το κινητό. Το βάζεις στο Supabase ως secret «APP_TOKEN», ώστε η γέφυρα να δέχεται μόνο εσένα. Μην το στείλεις σε κανέναν.', [
                        if (token == null)
                          FilledButton.icon(
                            key: const ValueKey('ai-make-token'),
                            onPressed: _makeToken,
                            icon: const Icon(Icons.key_rounded),
                            label: const Text('Φτιάξε κλειδί'),
                          )
                        else ...[
                          SelectableText(
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
                              onPressed: () => setState(() => _showToken = !_showToken),
                              child: Text(_showToken ? 'Κρύψ’ το' : 'Δείξ’ το'),
                            ),
                          ]),
                        ],
                      ]),
                      const SizedBox(height: 12),
                      step('2', 'Project ID του Supabase',
                          'Στο supabase.com, στο project της γέφυρας: Project Settings › General › Project ID.', [
                        TextField(
                          key: const ValueKey('ai-project-id'),
                          controller: _id,
                          autocorrect: false,
                          enableSuggestions: false,
                          decoration: const InputDecoration(hintText: 'π.χ. abcdefghij0123456789', border: OutlineInputBorder()),
                          onSubmitted: (_) => _saveId(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(key: const ValueKey('ai-save-id'), onPressed: _saveId, child: const Text('Αποθήκευση')),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      step('3', 'Δοκιμή', 'Ελέγχει ότι η γέφυρα και το Claude API απαντούν (μία πολύ μικρή ερώτηση).', [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const ValueKey('ai-test'),
                            onPressed: token != null && hasUrl && !_busy ? _try : null,
                            icon: _busy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_tethering_rounded),
                            label: const Text('Δοκιμή σύνδεσης'),
                          ),
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
                            subtitle: 'Αν το παλιό το είδε κάποιος άλλος.',
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
