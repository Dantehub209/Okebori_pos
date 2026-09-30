import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/pricing.dart';
import '../theme.dart';

/// What the signed-in cashier has collected today, split by payment method.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  List<Map<String, dynamic>>? _payments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final supabase = Supabase.instance.client;
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final rows = await supabase
          .from('payments')
          .select('amount, payment_method, paid_at, parcels(booking_number)')
          .eq('received_by', supabase.auth.currentUser!.id)
          .eq('status', 'COMPLETED')
          .gte('paid_at', startOfDay.toIso8601String())
          .order('paid_at', ascending: false);
      if (mounted) setState(() => _payments = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  double _total(String? method) => _payments!
      .where((p) => method == null || p['payment_method'] == method)
      .fold(0.0, (sum, p) => sum + (p['amount'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load your shift.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );
    }
    if (_payments == null) return const Center(child: CircularProgressIndicator());

    final payments = _payments!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text("TODAY, ${DateFormat('EEE d MMM').format(DateTime.now()).toUpperCase()}",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: AppColors.navy,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Collected', style: TextStyle(color: Color(0xFFB9BFCA))),
                  const SizedBox(height: 4),
                  Text('KSh ${formatKsh(_total(null))}',
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${payments.length} ${payments.length == 1 ? 'booking' : 'bookings'}',
                      style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w700)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Column(children: [
                  _row('Cash in drawer', _total('CASH')),
                  _row('M-Pesa', _total('MPESA')),
                  _row('Card', _total('CARD')),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No bookings yet today. Pull down to refresh.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
            )
          else ...[
            const Text('BOOKINGS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
            const SizedBox(height: 10),
            Card(
              margin: EdgeInsets.zero,
              child: Column(children: [
                for (final p in payments)
                  ListTile(
                    dense: true,
                    title: Text(p['parcels']?['booking_number']?.toString() ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${DateFormat('HH:mm').format(DateTime.parse(p['paid_at']).toLocal())} · ${_methodLabel(p['payment_method'])}'),
                    trailing: Text('KSh ${formatKsh((p['amount'] as num).toDouble())}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  String _methodLabel(String? code) => switch (code) {
        'CASH' => 'Cash',
        'MPESA' => 'M-Pesa',
        'CARD' => 'Card',
        _ => code ?? '',
      };

  Widget _row(String label, double amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 15, color: AppColors.muted))),
          Text('KSh ${formatKsh(amount)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      );
}
