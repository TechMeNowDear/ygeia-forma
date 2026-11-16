// «Εκτίμηση (δεν ζυγίστηκε)» (16/11): ο ίδιος διακόπτης στο φύλλο ποσότητας και στο φύλλο φαγητού.
import 'package:flutter/material.dart';

import '../theme.dart';

class EstimateSwitch extends StatelessWidget {
  const EstimateSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = Aigaio.of(context);
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        key: const ValueKey('estimate-switch'),
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text('Εκτίμηση (δεν ζυγίστηκε)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        subtitle: Text('Φαγητό έξω, τυπικό κομμάτι, «με το μάτι».',
            style: TextStyle(fontSize: 13, color: c.textSecondary)),
      ),
    );
  }
}
