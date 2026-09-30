import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/pricing.dart';
import 'admin_theme.dart';

/// Parcel statuses that mean the parcel is waiting at its destination branch.
const _onShelfStatuses = ['ARRIVED', 'READY_FOR_COLLECTION'];

/// Today's figures for the overview, already filtered to one branch for Branch Managers.
class OverviewData {
  final List<Map<String, dynamic>> branches; // id, name
  final List<Map<String, dynamic>> bookedToday; // origin_branch_id, shipping_charge
  final List<Map<String, dynamic>> paymentsToday; // branch_id, received_by, amount, payment_method
  final List<Map<String, dynamic>> onShelf; // destination_branch_id
  final List<Map<String, dynamic>> latest; // booking_number, shipping_charge, status, created_at, origin, destination
  final Map<String, Map<String, dynamic>> staff; // user id -> name, branch_id

  const OverviewData({
    required this.branches,
    required this.bookedToday,
    required this.paymentsToday,
    required this.onShelf,
    required this.latest,
    required this.staff,
  });

  static Future<OverviewData> load(String? branchId) async {
    final supabase = Supabase.instance.client;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();

    var branchQuery = supabase.from('branches').select('id, name');
    var bookedQuery = supabase.from('parcels').select('origin_branch_id, shipping_charge').gte('created_at', startOfDay);
    var paymentsQuery = supabase
        .from('payments')
        .select('branch_id, received_by, amount, payment_method')
        .eq('status', 'COMPLETED')
        .gte('paid_at', startOfDay);
    var shelfQuery = supabase.from('parcels').select('destination_branch_id').inFilter('status', _onShelfStatuses);
    var latestQuery = supabase.from('parcels').select(
        'booking_number, shipping_charge, status, created_at, origin:branches!origin_branch_id(name), destination:branches!destination_branch_id(name)');
    if (branchId != null) {
      branchQuery = branchQuery.eq('id', branchId);
      bookedQuery = bookedQuery.eq('origin_branch_id', branchId);
      paymentsQuery = paymentsQuery.eq('branch_id', branchId);
      shelfQuery = shelfQuery.eq('destination_branch_id', branchId);
      latestQuery = latestQuery.or('origin_branch_id.eq.$branchId,destination_branch_id.eq.$branchId');
    }

    final results = await Future.wait<dynamic>([
      branchQuery.order('name'),
      bookedQuery,
      paymentsQuery,
      shelfQuery,
      latestQuery.order('created_at', ascending: false).limit(8),
      supabase.from('users').select('id, name, branch_id'),
    ]);
    List<Map<String, dynamic>> rows(int i) => List<Map<String, dynamic>>.from(results[i]);

    return OverviewData(
      branches: rows(0),
      bookedToday: rows(1),
      paymentsToday: rows(2),
      onShelf: rows(3),
      latest: rows(4),
      staff: {for (final u in rows(5)) u['id'].toString(): u},
    );
  }
}

class _Totals {
  int bookings = 0;
  double booked = 0, cash = 0, mpesa = 0, card = 0;
  int onShelf = 0;
}

class OverviewScreen extends StatefulWidget {
  /// Null shows every branch (Super Admin); otherwise just that branch.
  final String? branchId;
  final Future<OverviewData> Function(String? branchId) loadData;

  const OverviewScreen({super.key, this.branchId, this.loadData = OverviewData.load});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  OverviewData? _data;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.loadData(widget.branchId);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  static double _amount(Map<String, dynamic> row, String key) => (row[key] as num?)?.toDouble() ?? 0;

  Map<String, _Totals> _byBranch(OverviewData d) {
    final totals = {for (final b in d.branches) b['id'].toString(): _Totals()};
    for (final p in d.bookedToday) {
      final t = totals[p['origin_branch_id']?.toString()];
      if (t == null) continue;
      t.bookings++;
      t.booked += _amount(p, 'shipping_charge');
    }
    for (final p in d.paymentsToday) {
      final t = totals[p['branch_id']?.toString()];
      if (t == null) continue;
      switch (p['payment_method']) {
        case 'CASH':
          t.cash += _amount(p, 'amount');
        case 'MPESA':
          t.mpesa += _amount(p, 'amount');
        case 'CARD':
          t.card += _amount(p, 'amount');
      }
    }
    for (final p in d.onShelf) {
      totals[p['destination_branch_id']?.toString()]?.onShelf++;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Could not load today\'s figures.\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(onPressed: _load, child: const Text('Try again')),
              ]),
      );
    }

    final byBranch = _byBranch(data);
    final all = _Totals();
    for (final t in byBranch.values) {
      all
        ..bookings += t.bookings
        ..booked += t.booked
        ..cash += t.cash
        ..mpesa += t.mpesa
        ..card += t.card
        ..onShelf += t.onShelf;
    }

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
          children: [
            Text(widget.branchId == null ? 'Today across the network' : 'Today at ${data.branches.firstOrNull?['name'] ?? 'your branch'}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AdminColors.text)),
            const SizedBox(height: 16),
            _statTiles(all, wide ? 6 : 2),
            const SizedBox(height: 14),
            _panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _branchTable(data, byBranch, all),
                const SizedBox(height: 12),
                Text(
                  'Booked value counts parcels sent from each branch. Cash, M-Pesa and card are payments taken at each branch. '
                  'On shelf is parcels waiting for collection. Refreshes every minute.',
                  style: const TextStyle(color: AdminColors.muted, fontSize: 12),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _cashiersPanel(data)),
                const SizedBox(width: 14),
                Expanded(child: _latestPanel(data)),
              ])
            else ...[
              _cashiersPanel(data),
              const SizedBox(height: 14),
              _latestPanel(data),
            ],
          ],
        ),
      );
    });
  }

  Widget _statTiles(_Totals all, int perRow) {
    final tiles = [
      ('${all.bookings}', 'Bookings'),
      ('KSh ${formatKsh(all.booked)}', 'Value booked'),
      ('KSh ${formatKsh(all.cash)}', 'Cash collected'),
      ('KSh ${formatKsh(all.mpesa)}', 'M-Pesa collected'),
      ('KSh ${formatKsh(all.card)}', 'Card collected'),
      ('${all.onShelf}', 'Parcels on shelves'),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final width = (c.maxWidth - gap * (perRow - 1)) / perRow;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (value, label) in tiles)
            SizedBox(
              width: width,
              child: _panel(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AdminColors.text)),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 13, color: AdminColors.muted)),
                ]),
              ),
            ),
        ],
      );
    });
  }

  Widget _branchTable(OverviewData data, Map<String, _Totals> byBranch, _Totals all) {
    const headers = ['Branch', 'Bookings', 'Booked value', 'Cash', 'M-Pesa', 'Card', 'On shelf'];
    List<String> cells(String name, _Totals t) => [
          name,
          '${t.bookings}',
          formatKsh(t.booked),
          formatKsh(t.cash),
          formatKsh(t.mpesa),
          formatKsh(t.card),
          '${t.onShelf}',
        ];

    return _table(
      headers: headers,
      rows: [
        for (final b in data.branches) cells(b['name'].toString(), byBranch[b['id'].toString()]!),
        if (data.branches.length > 1) cells('All branches', all),
      ],
      boldLastRow: data.branches.length > 1,
      flex: const [3, 2, 2, 2, 2, 2, 2],
      minWidth: 620,
    );
  }

  Widget _cashiersPanel(OverviewData data) {
    final byCashier = <String, ({int count, double total})>{};
    for (final p in data.paymentsToday) {
      final id = p['received_by']?.toString() ?? '';
      final prev = byCashier[id] ?? (count: 0, total: 0.0);
      byCashier[id] = (count: prev.count + 1, total: prev.total + _amount(p, 'amount'));
    }
    final branchNames = {for (final b in data.branches) b['id'].toString(): b['name'].toString()};
    final entries = byCashier.entries.toList()..sort((a, b) => b.value.total.compareTo(a.value.total));

    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _panelTitle('Cashiers working today'),
        if (entries.isEmpty)
          const Text('No payments taken yet.', style: TextStyle(color: AdminColors.muted))
        else
          _table(
            headers: const ['Cashier', 'Branch', 'Bookings', 'Collected'],
            flex: const [3, 3, 2, 2],
            rows: [
              for (final e in entries)
                [
                  data.staff[e.key]?['name']?.toString() ?? 'Unknown',
                  branchNames[data.staff[e.key]?['branch_id']?.toString()] ?? '-',
                  '${e.value.count}',
                  formatKsh(e.value.total),
                ],
            ],
          ),
      ]),
    );
  }

  Widget _latestPanel(OverviewData data) {
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _panelTitle('Latest bookings'),
        if (data.latest.isEmpty)
          const Text('No bookings yet.', style: TextStyle(color: AdminColors.muted))
        else
          _table(
            headers: const ['Booking', 'Route', 'Booked', 'Amount'],
            flex: const [3, 3, 2, 2],
            rows: [
              for (final p in data.latest)
                [
                  p['booking_number']?.toString() ?? '-',
                  '${p['origin']?['name'] ?? '?'} to ${p['destination']?['name'] ?? '?'}',
                  DateFormat('d MMM, HH:mm').format(DateTime.parse(p['created_at']).toLocal()),
                  formatKsh(_amount(p, 'shipping_charge')),
                ],
            ],
          ),
      ]),
    );
  }

  Widget _panelTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AdminColors.text)),
      );

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AdminColors.border),
        ),
        child: child,
      );

  /// Simple table: first column left-aligned, the rest right-aligned like the figures they hold.
  Widget _table({required List<String> headers, required List<List<String>> rows, required List<int> flex, bool boldLastRow = false, double minWidth = 400}) {
    Widget row(List<String> cells, {bool header = false, bool bold = false, bool divider = true}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            border: divider ? const Border(bottom: BorderSide(color: AdminColors.border)) : null,
          ),
          child: Row(children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: flex[i],
                child: Text(
                  cells[i],
                  textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: header ? 12 : 14,
                    color: header ? AdminColors.muted : AdminColors.text,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
          ]),
        );

    final table = Column(children: [
      row(headers, header: true),
      for (var i = 0; i < rows.length; i++)
        row(rows[i], bold: boldLastRow && i == rows.length - 1, divider: i < rows.length - 1 || boldLastRow),
    ]);
    // Keep columns readable on narrow screens by scrolling sideways instead of squashing.
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= minWidth) return table;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, child: table));
    });
  }
}
