import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/register_user_screen.dart';
import 'admin_theme.dart';

/// Lists staff accounts with their role and branch.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  List<Map<String, dynamic>>? _users;
  Map<String, String> _roles = {};
  Map<String, String> _branches = {};
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
      final users = await supabase.from('users').select('id, name, email, phone, status, role_id, branch_id').order('name');
      final roles = await supabase.from('roles').select('id, name');
      final branches = await supabase.from('branches').select('id, name');
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(users);
        _roles = {for (final r in roles) r['id'].toString(): r['name'].toString()};
        _branches = {for (final b in branches) b['id'].toString(): b['name'].toString()};
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _addStaff() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterUserScreen()));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: _addStaff,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add staff'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Could not load staff.\n$_error', textAlign: TextAlign.center))
          : users == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(children: [
                        for (final u in users)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AdminColors.selected,
                              child: Text((u['name'] ?? '?').toString().characters.first.toUpperCase(),
                                  style: const TextStyle(color: AdminColors.text, fontWeight: FontWeight.w700)),
                            ),
                            title: Text(u['name'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([u['email'], u['phone']].where((v) => v != null && '$v'.isNotEmpty).join(' · ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_roles[u['role_id']?.toString()] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text(
                                  '${_branches[u['branch_id']?.toString()] ?? 'No branch'}${u['status'] == 'active' ? '' : ' · ${u['status']}'}',
                                  style: const TextStyle(color: AdminColors.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                      ]),
                    ),
                  ],
                ),
    );
  }
}
