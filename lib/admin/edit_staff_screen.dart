import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_theme.dart';

/// Edits a staff member through the update-staff server function
/// (supabase/functions/update-staff), which also changes their login.
class EditStaffScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final Map<String, String> roles; // id -> name
  final Map<String, String> branches; // id -> name

  const EditStaffScreen({super.key, required this.user, required this.roles, required this.branches});

  @override
  State<EditStaffScreen> createState() => _EditStaffScreenState();
}

class _EditStaffScreenState extends State<EditStaffScreen> {
  late final _name = TextEditingController(text: widget.user['name'] ?? '');
  late final _email = TextEditingController(text: widget.user['email'] ?? '');
  late final _phone = TextEditingController(text: widget.user['phone'] ?? '');
  final _password = TextEditingController();
  late String? _roleId = _known(widget.roles, widget.user['role_id']);
  late String? _branchId = _known(widget.branches, widget.user['branch_id']);
  late bool _active = (widget.user['status'] ?? 'active').toString().toLowerCase() == 'active';
  bool _saving = false;

  bool get _isMe => widget.user['id'] == Supabase.instance.client.auth.currentUser?.id;

  static String? _known(Map<String, String> options, dynamic id) =>
      id != null && options.containsKey(id.toString()) ? id.toString() : null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? AdminColors.errorText : AdminColors.successText),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _roleId == null || _branchId == null) {
      _message('Name, email, role and branch are required.', error: true);
      return;
    }
    if (_password.text.isNotEmpty && _password.text.length < 6) {
      _message('New password must be at least 6 characters.', error: true);
      return;
    }
    if (!_active && !await _confirmDeactivate()) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.functions.invoke('update-staff', body: {
        'id': widget.user['id'],
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'password': _password.text.isEmpty ? null : _password.text,
        'role_id': _roleId,
        'branch_id': _branchId,
        'status': _active ? 'active' : 'inactive',
      });
      if (!mounted) return;
      _message('Saved ${_name.text.trim()}.');
      Navigator.pop(context, true);
    } catch (e) {
      final message = e is FunctionException && e.details is Map ? e.details['error'] : '$e';
      if (mounted) _message('Could not save: $message', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDeactivate() async {
    final wasActive = (widget.user['status'] ?? 'active').toString().toLowerCase() == 'active';
    if (!wasActive) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate ${_name.text.trim()}?'),
        content: const Text(
            'They will be signed out of the app and cannot sign in again until you reactivate them. '
            'Their past bookings and payments are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit ${widget.user['name'] ?? 'staff'}')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _section('Details'),
                    TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(labelText: 'Phone number'),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email (used to sign in)'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: _dropdown('Role', _roleId, widget.roles, _isMe ? null : (v) => setState(() => _roleId = v))),
                      const SizedBox(width: 14),
                      Expanded(child: _dropdown('Branch', _branchId, widget.branches, (v) => setState(() => _branchId = v))),
                    ]),
                    if (_isMe)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text("You can't change your own role or deactivate yourself.",
                            style: TextStyle(color: AdminColors.muted, fontSize: 12)),
                      ),
                    const SizedBox(height: 24),
                    _section('Sign-in'),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: 'Leave empty to keep their current password',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _active,
                      onChanged: _isMe ? null : (v) => setState(() => _active = v),
                      activeThumbColor: AdminColors.orange,
                      title: const Text('Active'),
                      subtitle: Text(_active
                          ? 'Can sign in and use the app'
                          : 'Blocked: signed out and cannot sign in'),
                    ),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save changes'),
                      ),
                    ]),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AdminColors.muted)),
      );

  Widget _dropdown(String label, String? value, Map<String, String> options, ValueChanged<String?>? onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: onChanged,
    );
  }
}
