import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_theme.dart';

/// Customers with how many parcels they sent or received; Super Admins can delete them
/// (supabase/delete_records.sql).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Map<String, dynamic>>? _customers;
  Map<String, int> _parcelCounts = {};
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final supabase = Supabase.instance.client;
      final customers = await supabase.from('customers').select('id, name, phone, email').order('name');
      final parcels = await supabase.from('parcels').select('sender_id, receiver_id');
      final counts = <String, int>{};
      for (final p in parcels) {
        for (final id in {p['sender_id']?.toString(), p['receiver_id']?.toString()}) {
          if (id != null) counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _customers = List<Map<String, dynamic>>.from(customers);
        _parcelCounts = counts;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? AdminColors.errorText : AdminColors.successText),
    );
  }

  Future<void> _delete(Map<String, dynamic> customer) async {
    final parcels = _parcelCounts[customer['id'].toString()] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${customer['name'] ?? 'customer'}?'),
        content: Text(parcels == 0
            ? 'This cannot be undone.'
            : 'They are on $parcels parcel(s) as sender or receiver. Those parcels, with their payments, '
                'receipts and tracking, will be deleted too and disappear from reports.\n\nThis cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.errorText),
            child: Text(parcels == 0 ? 'Delete' : 'Delete with $parcels parcel(s)'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc('delete_customer', params: {
        'p_customer_id': customer['id'].toString(),
        'p_with_parcels': parcels > 0,
      });
      _message('Deleted ${customer['name'] ?? 'customer'}.');
      _load();
    } catch (e) {
      _message(e is PostgrestException ? e.message : '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final shown = (_customers ?? [])
        .where((c) =>
            query.isEmpty ||
            (c['name'] ?? '').toString().toLowerCase().contains(query) ||
            (c['phone'] ?? '').toString().contains(query))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      body: _error != null
          ? Center(child: Text('Could not load customers.\n$_error', textAlign: TextAlign.center))
          : _customers == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search)),
                    ),
                    const SizedBox(height: 12),
                    Text('${shown.length} of ${_customers!.length} customers',
                        style: const TextStyle(color: AdminColors.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(children: [
                        for (final c in shown)
                          ListTile(
                            title: Text(c['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([c['phone'], c['email']].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('${_parcelCounts[c['id'].toString()] ?? 0} parcels',
                                  style: const TextStyle(color: AdminColors.muted)),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Delete customer',
                                icon: const Icon(Icons.delete_outline, color: AdminColors.errorText),
                                onPressed: () => _delete(c),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ),
    );
  }
}
