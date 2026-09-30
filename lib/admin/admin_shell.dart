import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/branch_reports_screen.dart';
import '../screens/manage_branches_screen.dart';
import '../screens/parcels_list_screen.dart';
import '../screens/pricing_rules_screen.dart';
import '../services/staff_profile.dart';
import '../theme.dart';
import 'app_version_screen.dart';
import 'staff_screen.dart';

class _Page {
  final String label;
  final IconData icon;
  final Widget Function(StaffProfile profile) builder;
  const _Page(this.label, this.icon, this.builder);
}

/// Sidebar layout for the web admin. Super Admins see everything;
/// Branch Managers see reports and parcels for their branch.
class AdminShell extends StatefulWidget {
  final VoidCallback onSignedOut;
  final Future<StaffProfile> Function() loadProfile;

  const AdminShell({super.key, required this.onSignedOut, this.loadProfile = StaffProfile.load});

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

  List<_Page> _pagesFor(StaffProfile profile) {
    final superAdmin = profile.role == 'Super Admin';
    return [
      _Page('Reports', Icons.analytics_outlined, (p) => BranchReportsScreen(
            branchId: superAdmin ? null : p.branchId,
            reportTitle: superAdmin ? 'All branches' : p.branchName,
          )),
      _Page('Parcels', Icons.inventory_2_outlined, (p) => const ParcelsListScreen()),
      if (superAdmin) ...[
        _Page('Branches', Icons.store_outlined, (p) => const ManageBranchesScreen()),
        _Page('Pricing', Icons.price_change_outlined, (p) => const PricingRulesScreen()),
        _Page('Staff', Icons.people_outline, (p) => const StaffScreen()),
        _Page('App updates', Icons.system_update_outlined, (p) => const AppVersionScreen()),
      ],
    ];
  }

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

    if (profile.role != 'Super Admin' && profile.role != 'Branch Manager') {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 48, color: AppColors.muted),
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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        // Pages keep their own AppBar; here it reads as a plain page title.
        child: Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.text,
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text),
            ),
          ),
          child: KeyedSubtree(key: ValueKey('$index-$_visits'), child: pages[index].builder(profile)),
        ),
      ),
    );

    void select(int i) => setState(() {
          if (i != _index) _visits++;
          _index = i;
        });

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        automaticallyImplyLeading: !wide,
        title: Row(children: [
          const Text('Okebori Admin', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Container(width: 1, height: 20, color: const Color(0xFF5A6273)),
          const SizedBox(width: 12),
          Flexible(
            child: Text('${profile.name}, ${profile.role}',
                overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: Color(0xFFB9BFCA))),
          ),
        ]),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(3),
          child: ColoredBox(color: AppColors.orange, child: SizedBox(height: 3, width: double.infinity)),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: _signOut,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF5A6273)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: const Text('Sign out'),
            ),
          ),
        ],
      ),
      drawer: wide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(children: [
                  for (var i = 0; i < pages.length; i++)
                    ListTile(
                      leading: Icon(pages[i].icon, color: i == index ? AppColors.orange : AppColors.muted),
                      title: Text(pages[i].label,
                          style: TextStyle(fontWeight: i == index ? FontWeight.w700 : FontWeight.w500)),
                      selected: i == index,
                      onTap: () {
                        Navigator.pop(context);
                        select(i);
                      },
                    ),
                ]),
              ),
            ),
      body: wide
          ? Row(children: [
              NavigationRail(
                extended: true,
                minExtendedWidth: 210,
                backgroundColor: Colors.white,
                selectedIndex: index,
                onDestinationSelected: select,
                indicatorColor: AppColors.orange.withValues(alpha: 0.12),
                selectedIconTheme: const IconThemeData(color: AppColors.orange),
                selectedLabelTextStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                unselectedLabelTextStyle: const TextStyle(color: AppColors.muted),
                destinations: [
                  for (final p in pages) NavigationRailDestination(icon: Icon(p.icon), label: Text(p.label)),
                ],
              ),
              const VerticalDivider(width: 1, color: AppColors.border),
              Expanded(child: content),
            ])
          : content,
    );
  }
}
