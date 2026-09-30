import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/staff_profile.dart';
import '../theme.dart';
import '../widgets/printer_picker.dart';
import 'booking_screen.dart';
import 'parcels_list_screen.dart';
import 'settings_screen.dart';

/// Main screen after sign-in: branch header, and Book / Parcels / Settings tabs.
class HomeShell extends StatefulWidget {
  final VoidCallback onSignedOut;
  final Future<StaffProfile> Function() loadProfile;
  final Future<BookingSetup> Function() loadBookingSetup;

  const HomeShell({
    super.key,
    required this.onSignedOut,
    this.loadProfile = StaffProfile.load,
    this.loadBookingSetup = BookingSetup.load,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabs = ['Book', 'Parcels', 'Settings'];

  StaffProfile? _profile;
  String? _error;
  int _tab = 0;
  int _parcelsVersion = 0; // Bumped on each visit so the list reloads

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
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

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      body: Column(
        children: [
          _header(profile),
          Expanded(
            child: profile == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('Could not load your profile.\n$_error', textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              OutlinedButton(onPressed: _loadProfile, child: const Text('Try again')),
                            ]),
                          ),
                  )
                : IndexedStack(
                    index: _tab,
                    children: [
                      BookingScreen(profile: profile, loadSetup: widget.loadBookingSetup),
                      _tab == 1 ? ParcelsListScreen(key: ValueKey(_parcelsVersion)) : const SizedBox.shrink(),
                      const SettingsScreen(),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _bottomTabs(),
    );
  }

  Widget _header(StaffProfile? profile) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navy,
        border: Border(bottom: BorderSide(color: AppColors.orange, width: 3)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile?.branchName ?? 'Okebori POS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(profile == null ? '' : '${profile.name}, ${profile.role}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFB9BFCA), fontSize: 13)),
                  ],
                ),
              ),
              _headerButton('Printer', () => showPrinterPicker(context)),
              const SizedBox(width: 8),
              _headerButton('Sign out', _signOut),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerButton(String label, VoidCallback onPressed) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF5A6273)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Widget _bottomTabs() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final selected = i == _tab;
            return Expanded(
              child: InkWell(
                onTap: () => setState(() {
                  if (i == 1 && _tab != 1) _parcelsVersion++;
                  _tab = i;
                }),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: selected ? AppColors.orange : Colors.transparent, width: 3)),
                  ),
                  child: Text(_tabs[i],
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AppColors.text : AppColors.muted,
                      )),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
