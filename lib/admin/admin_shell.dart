import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/manage_branches_screen.dart';
import '../screens/parcels_list_screen.dart';
import '../screens/pricing_rules_screen.dart';
import '../services/staff_profile.dart';
import 'admin_theme.dart';
import 'app_version_screen.dart';
import 'customers_screen.dart';
import 'etims_screen.dart';
import 'overview_screen.dart';
import 'staff_screen.dart';

class _Page {
  final String label;
  final Widget Function(StaffProfile profile) builder;
  const _Page(this.label, this.builder);
}

/// Top-menu layout for the web admin. Super Admins see everything;
/// Branch Managers see the overview and parcels for their branch.
class AdminShell extends StatefulWidget {
  final VoidCallback onSignedOut;
  final Future<StaffProfile> Function() loadProfile;
  final Future<OverviewData> Function(String? branchId) loadOverview;

  const AdminShell({
    super.key,
    required this.onSignedOut,
    this.loadProfile = StaffProfile.load,
    this.loadOverview = OverviewData.load,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  StaffProfile? _profile;
  String? _error;
  int _index = 0;
  int _visits = 0; // Bumped on each page switch so pages reload fresh data

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final profile = await widget.loadProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    widget.onSignedOut();
  }

  bool _isSuperAdmin(StaffProfile p) => p.role == 'Super Admin';

  List<_Page> _pagesFor(StaffProfile profile) => [
        _Page('Overview', (p) => OverviewScreen(branchId: _isSuperAdmin(p) ? null : p.branchId, loadData: widget.loadOverview)),
        _Page('Parcels', (p) => const ParcelsListScreen()),
        if (_isSuperAdmin(profile)) ...[
          _Page('Branches', (p) => const ManageBranchesScreen()),
          _Page('Pricing', (p) => const PricingRulesScreen()),
          _Page('Customers', (p) => const CustomersScreen()),
          _Page('Staff', (p) => const StaffScreen()),
          _Page('eTIMS', (p) => const EtimsScreen()),
          _Page('App updates', (p) => const AppVersionScreen()),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Could not load your profile.\n$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: _load, child: const Text('Try again')),
                  TextButton(onPressed: _signOut, child: const Text('Sign out')),
                ]),
        ),
      );
    }

    if (!_isSuperAdmin(profile) && profile.role != 'Branch Manager') {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 48, color: AdminColors.muted),
              const SizedBox(height: 16),
              Text('${profile.name}, the admin page is for managers only.\nUse the Okebori POS app on your phone.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _signOut, child: const Text('Sign out')),
            ]),
          ),
        ),
      );
    }

    final pages = _pagesFor(profile);
    final index = _index.clamp(0, pages.length - 1);

    return Scaffold(
      body: Column(children: [
        _topBar(profile, pages, index),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: KeyedSubtree(key: ValueKey('$index-$_visits'), child: pages[index].builder(profile)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _topBar(StaffProfile profile, List<_Page> pages, int index) {
    return Container(
      decoration: const BoxDecoration(
        color: AdminColors.header,
        border: Border(bottom: BorderSide(color: AdminColors.orange, width: 3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        const Text('Okebori', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AdminColors.text)),
        const SizedBox(width: 8),
        Text(_isSuperAdmin(profile) ? 'Head office' : profile.branchName,
            style: const TextStyle(fontSize: 14, color: AdminColors.muted)),
        const SizedBox(width: 20),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < pages.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton(
                    onPressed: () => setState(() {
                      if (i != _index) _visits++;
                      _index = i;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: i == index ? AdminColors.text : const Color(0xFFC9D1D9),
                      backgroundColor: i == index ? AdminColors.selected : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      textStyle: TextStyle(fontSize: 15, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500),
                    ),
                    child: Text(pages[i].label),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: '${profile.name}, ${profile.role}',
          child: OutlinedButton(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)),
            child: const Text('Sign out'),
          ),
        ),
      ]),
    );
  }
}
