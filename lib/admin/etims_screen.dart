import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/pricing.dart';
import 'admin_theme.dart';

/// eTIMS mode switch and the list of invoices and credit notes (supabase/etims.sql).
class EtimsScreen extends StatefulWidget {
  const EtimsScreen({super.key});

  @override
  State<EtimsScreen> createState() => _EtimsScreenState();
}

class _EtimsScreenState extends State<EtimsScreen> {
  static const _modes = {
    'off': ('Off', 'No invoices are created.'),
    'simulation': ('Simulation', 'Invoices get pretend KRA numbers and print "SIMULATION – NOT A TAX INVOICE". For testing.'),
    'sandbox': ('KRA sandbox', "Invoices go to KRA's test system. Needs KRA sandbox details."),
    'production': ('Live', 'Real tax invoices sent to KRA. Needs KRA approval.'),
  };

  Map<String, dynamic>? _config;
  List<Map<String, dynamic>>? _invoices;
  String? _error;
  String _filterMode = 'all';
  final _kraPin = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kraPin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final supabase = Supabase.instance.client;
      final config = await supabase.from('etims_config').select().eq('id', 1).maybeSingle();
      final invoices = await supabase
          .from('etims_invoices')
          .select('id, mode, invoice_type, invoice_number, status, kra_receipt_number, total_amount, vat_amount, '
              'customer_name, customer_kra_pin, last_error, created_at, parcel_id')
          .order('created_at', ascending: false)
          .limit(200);
      final list = List<Map<String, dynamic>>.from(invoices);
      final parcelIds = list.map((i) => i['parcel_id'].toString()).toSet().toList();
      final parcels = parcelIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await supabase.from('parcels').select('id, booking_number').inFilter('id', parcelIds));
      final bookingNumbers = {for (final p in parcels) p['id'].toString(): p['booking_number']};
      if (!mounted) return;
      setState(() {
        _config = config;
        _kraPin.text = config?['kra_pin'] ?? '';
        _invoices = [for (final i in list) {...i, 'booking_number': bookingNumbers[i['parcel_id'].toString()]}];
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'eTIMS is not set up yet. Run supabase/etims.sql in the Supabase SQL editor.\n\n$e');
      }
    }
  }

  Future<void> _setMode(String mode) async {
    if (mode == 'production' &&
        await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Switch eTIMS to Live?'),
                content: const Text('Every paid booking will create a real tax invoice at KRA. '
                    'Only do this after KRA has approved your system and the live details are set.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Go live')),
                ],
              ),
            ) !=
            true) {
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.rpc('etims_set_mode', params: {'p_mode': mode, 'p_kra_pin': _kraPin.text.trim()});
      await _load();
      if (mounted) _snack('eTIMS is now: ${_modes[mode]!.$1}');
    } catch (e) {
      if (mounted) _snack(e is PostgrestException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), backgroundColor: error ? AdminColors.errorText : AdminColors.successText),
      );

  @override
  Widget build(BuildContext context) {
    final mode = (_config?['mode'] ?? 'off').toString();
    final shown = (_invoices ?? []).where((i) => _filterMode == 'all' || i['mode'] == _filterMode).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('eTIMS (KRA)')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _invoices == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final entry in _modes.entries)
                            ChoiceChip(
                              label: Text(entry.value.$1),
                              selected: mode == entry.key,
                              selectedColor: AdminColors.orange.withValues(alpha: 0.25),
                              onSelected: _saving || mode == entry.key ? null : (_) => _setMode(entry.key),
                            ),
                        ]),
                        const SizedBox(height: 8),
                        Text(_modes[mode]?.$2 ?? '', style: const TextStyle(color: AdminColors.muted)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _kraPin,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Business KRA PIN',
                              helperText: 'Saved when you change mode',
                            ),
                          ),
                        ),
                        if (mode == 'sandbox' || mode == 'production')
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Invoices are queued and sent by the etims-sync server function, which is set up once KRA '
                              'issues your sandbox details. Until then they wait in the queue.',
                              style: TextStyle(color: AdminColors.orange),
                            ),
                          ),
                      ])),
                      const SizedBox(height: 16),
                      Row(children: [
                        const Text('Invoices', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _filterMode,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('All modes')),
                            for (final entry in _modes.entries.where((e) => e.key != 'off'))
                              DropdownMenuItem(value: entry.key, child: Text(entry.value.$1)),
                          ],
                          onChanged: (v) => setState(() => _filterMode = v ?? 'all'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No invoices yet. Switch to Simulation and make a test booking.',
                              textAlign: TextAlign.center, style: TextStyle(color: AdminColors.muted)),
                        )
                      else
                        _panel(Column(children: [for (final inv in shown) _invoiceRow(inv)]), padding: EdgeInsets.zero),
                    ],
                  ),
                ),
    );
  }

  Widget _invoiceRow(Map<String, dynamic> inv) {
    final credit = inv['invoice_type'] == 'CREDIT_NOTE';
    final status = inv['status'].toString();
    final statusColor = switch (status) {
      'signed' => AdminColors.successText,
      'failed' => AdminColors.errorText,
      _ => AdminColors.orange,
    };
    final total = (inv['total_amount'] as num).toDouble();
    return ListTile(
      title: Row(children: [
        Text('${credit ? 'Credit note' : 'Invoice'} #${inv['invoice_number']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        if (inv['mode'] != 'production') _tag(_modes[inv['mode']]?.$1 ?? inv['mode'], AdminColors.muted),
        const SizedBox(width: 6),
        _tag(status, statusColor),
      ]),
      subtitle: Text([
        inv['booking_number'],
        inv['customer_name'],
        inv['customer_kra_pin'],
        inv['kra_receipt_number'],
        DateFormat('d MMM, HH:mm').format(DateTime.parse(inv['created_at']).toLocal()),
        if (status == 'failed') inv['last_error'],
      ].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${credit ? '-' : ''}KSh ${formatKsh(total)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('VAT ${formatKsh((inv['vat_amount'] as num).toDouble())}', style: const TextStyle(color: AdminColors.muted, fontSize: 12)),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11)),
      );

  Widget _panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.border),
        ),
        child: child,
      );
}
