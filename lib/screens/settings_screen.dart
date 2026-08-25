import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'register_user_screen.dart';
import 'manage_branches_screen.dart';
import 'pricing_rules_screen.dart';
import 'branch_reports_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _userRole = 'Loading...';
  String _userName = 'User';
  String? _userBranchId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      final userResponse = await supabase
          .from('users')
          .select('name, role_id, branch_id')
          .eq('id', userId)
          .single();

      String roleName = 'Unknown';
      if (userResponse['role_id'] != null) {
        final roleResponse = await supabase
            .from('roles')
            .select('name')
            .eq('id', userResponse['role_id'])
            .single();
        roleName = roleResponse['name'] ?? 'Unknown';
      }

      setState(() {
        _userName = userResponse['name'] ?? 'User';
        _userRole = roleName;
        _userBranchId = userResponse['branch_id'];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _userRole = 'Cashier';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final isSuperAdmin = _userRole == 'Super Admin';
    final isBranchManager = _userRole == 'Branch Manager';
    final hasAccess = isSuperAdmin || isBranchManager;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const CircleAvatar(radius: 30, child: Icon(Icons.admin_panel_settings, size: 30)),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(_userRole, style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (!hasAccess)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'Access Denied.\nOnly Administrators and Managers can access settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  children: [
                    // 1. Register User (Super Admin Only)
                    if (isSuperAdmin)
                      _buildSettingsTile(Icons.person_add, 'Register New User', 'Add cashiers, managers, or riders', () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterUserScreen()));
                      }),
                    
                    // 2. Manage Branches (Super Admin Only)
                    if (isSuperAdmin)
                      _buildSettingsTile(Icons.store, 'Manage Branches', 'Add or edit branch locations & GPS', () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageBranchesScreen()));
                      }),
                    
                    // 3. Pricing Rules (Super Admin Only)
                    if (isSuperAdmin)
                      _buildSettingsTile(Icons.price_change, 'Pricing Rules', 'Update base rates and fuel costs', () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const PricingRulesScreen()));
                      }),
                    
                    // 4. Branch Reports (Super Admin AND Branch Manager)
                    if (isBranchManager || isSuperAdmin)
                      _buildSettingsTile(Icons.analytics, 'Branch Reports', 'View daily collections and statistics', () {
                        Navigator.push(
                          context, 
                          MaterialPageRoute(
                            builder: (context) => BranchReportsScreen(
                              branchId: isSuperAdmin ? null : _userBranchId, 
                              reportTitle: isSuperAdmin ? 'Global Report (All Branches)' : 'Branch Daily Report',
                            ),
                          ),
                        );
                      }),

                    // Message for Cashiers
                    if (_userRole == 'Cashier')
                      const Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text(
                          'Limited Access.\nCashiers can only view basic settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.orange),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: Colors.indigo, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}