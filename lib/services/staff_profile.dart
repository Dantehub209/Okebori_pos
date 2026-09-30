import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in staff member, shown in the header and used as the booking origin.
class StaffProfile {
  final String name;
  final String role;
  final String? branchId;
  final String branchName;

  const StaffProfile({required this.name, required this.role, required this.branchId, required this.branchName});

  static Future<StaffProfile> load() async {
    final supabase = Supabase.instance.client;
    final user = await supabase
        .from('users')
        .select('name, role_id, branch_id')
        .eq('id', supabase.auth.currentUser!.id)
        .single();

    String role = 'Cashier';
    if (user['role_id'] != null) {
      final res = await supabase.from('roles').select('name').eq('id', user['role_id']).maybeSingle();
      role = res?['name'] ?? role;
    }

    String branchName = 'No branch';
    if (user['branch_id'] != null) {
      final res = await supabase.from('branches').select('name').eq('id', user['branch_id']).maybeSingle();
      branchName = res?['name'] ?? branchName;
    }

    return StaffProfile(
      name: user['name'] ?? 'Staff',
      role: role,
      branchId: user['branch_id'],
      branchName: branchName,
    );
  }
}
