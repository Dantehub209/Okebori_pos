import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/coordinates.dart';
import '../services/pricing.dart';
import '../theme.dart';

/// Branches with their GPS location, and the distances used for pricing.
class ManageBranchesScreen extends StatefulWidget {
  const ManageBranchesScreen({super.key});

  @override
  State<ManageBranchesScreen> createState() => _ManageBranchesScreenState();
}

class _ManageBranchesScreenState extends State<ManageBranchesScreen> {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await Supabase.instance.client.from('branches').select('*').order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _branches = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _isLoading = false;
        });
      }
    }
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? AppColors.errorText : AppColors.successText),
    );
  }

  static ({double lat, double lon})? _gps(Map<String, dynamic> b) {
    final lat = (b['latitude'] as num?)?.toDouble(), lon = (b['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null || (lat == 0 && lon == 0)) return null;
    return (lat: lat, lon: lon);
  }

  Future<void> _openEditor([Map<String, dynamic>? branch]) async {
    final saved = await showDialog<bool>(context: context, builder: (context) => _BranchDialog(branch: branch));
    if (saved == true) {
      _message(branch == null ? 'Branch added.' : 'Branch saved.');
      _loadBranches();
    }
  }

  Future<void> _toggleBranchStatus(Map<String, dynamic> branch) async {
    final newStatus = branch['status'] == 'active' ? 'inactive' : 'active';
    try {
      await Supabase.instance.client.from('branches').update({'status': newStatus}).eq('id', branch['id']);
      _message('${branch['name']} ${newStatus == 'active' ? 'activated' : 'deactivated'}.');
      _loadBranches();
    } catch (e) {
      _message('Error: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () => _openEditor(),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              icon: const Icon(Icons.add),
              label: const Text('Add branch'),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not load branches.\n$_error', textAlign: TextAlign.center))
              : RefreshIndicator(
                  onRefresh: _loadBranches,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        margin: EdgeInsets.zero,
                        child: Column(children: [
                          for (final b in _branches) _branchTile(b),
                        ]),
                      ),
                      const SizedBox(height: 24),
                      _distanceTable(),
                    ],
                  ),
                ),
    );
  }

  Widget _branchTile(Map<String, dynamic> b) {
    final isActive = b['status'] == 'active';
    final gps = _gps(b);
    return ListTile(
      onTap: () => _openEditor(b),
      leading: CircleAvatar(
        backgroundColor: isActive ? AppColors.orange.withValues(alpha: 0.15) : AppColors.selected,
        child: Icon(Icons.store, color: isActive ? AppColors.orange : AppColors.muted),
      ),
      title: Text('${b['name']}  ·  ${b['code'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        gps == null
            ? 'No GPS location: bookings to or from here cannot be priced'
            : 'GPS ${gps.lat.toStringAsFixed(5)}, ${gps.lon.toStringAsFixed(5)}'
                '${(b['address'] ?? '').toString().isNotEmpty ? '  ·  ${b['address']}' : ''}',
        style: TextStyle(color: gps == null ? AppColors.errorText : AppColors.muted),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Tooltip(
          message: isActive ? 'Active' : 'Inactive',
          child: Switch(value: isActive, activeThumbColor: AppColors.orange, onChanged: (_) => _toggleBranchStatus(b)),
        ),
        IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: () => _openEditor(b)),
      ]),
    );
  }

  /// Straight-line km between every pair of active branches that have GPS.
  Widget _distanceTable() {
    final located = _branches.where((b) => b['status'] == 'active' && _gps(b) != null).toList();
    String label(Map<String, dynamic> b) => (b['code'] ?? b['name']).toString();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Distances between branches (km)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Straight-line distance from the GPS locations above. Prices use these numbers.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          if (located.length < 2)
            const Text('Add GPS locations to at least two active branches to see distances.', style: TextStyle(color: AppColors.muted))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 40,
                columnSpacing: 20,
                columns: [
                  const DataColumn(label: Text('')),
                  for (final b in located) DataColumn(numeric: true, label: Text(label(b), style: const TextStyle(color: AppColors.muted))),
                ],
                rows: [
                  for (final from in located)
                    DataRow(cells: [
                      DataCell(Text(from['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final to in located)
                        DataCell(Text(from['id'] == to['id']
                            ? '–'
                            : distanceBetween(_gps(from)!.lat, _gps(from)!.lon, _gps(to)!.lat, _gps(to)!.lon).round().toString())),
                    ]),
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

/// Add or edit one branch. Coordinates can be typed or pasted from a Google Maps link.
class _BranchDialog extends StatefulWidget {
  final Map<String, dynamic>? branch;
  const _BranchDialog({this.branch});

  @override
  State<_BranchDialog> createState() => _BranchDialogState();
}

class _BranchDialogState extends State<_BranchDialog> {
  late final _name = TextEditingController(text: widget.branch?['name'] ?? '');
  late final _code = TextEditingController(text: widget.branch?['code'] ?? '');
  late final _address = TextEditingController(text: widget.branch?['address'] ?? '');
  late final _lat = TextEditingController(text: _initial('latitude'));
  late final _lon = TextEditingController(text: _initial('longitude'));
  final _mapsLink = TextEditingController();
  String? _linkHint;
  bool _saving = false;

  String _initial(String key) {
    final v = (widget.branch?[key] as num?)?.toDouble();
    final lat = (widget.branch?['latitude'] as num?)?.toDouble(), lon = (widget.branch?['longitude'] as num?)?.toDouble();
    if (v == null || (lat == 0 && lon == 0)) return '';
    return v.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _address, _lat, _lon, _mapsLink]) {
      c.dispose();
    }
    super.dispose();
  }

  void _readLink(String text) {
    if (text.trim().isEmpty) {
      setState(() => _linkHint = null);
      return;
    }
    final gps = parseCoordinates(text);
    setState(() {
      if (gps != null) {
        _lat.text = gps.lat.toString();
        _lon.text = gps.lon.toString();
        _linkHint = 'Location filled in from the link.';
      } else {
        _linkHint = 'No coordinates in that link. Open it in Google Maps on a computer and copy the full address bar, '
            'or long-press the spot in the Maps app and copy the numbers it shows.';
      }
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim(), code = _code.text.trim().toUpperCase();
    final latText = _lat.text.trim(), lonText = _lon.text.trim();
    final lat = double.tryParse(latText), lon = double.tryParse(lonText);
    String? problem;
    if (name.isEmpty || code.isEmpty) {
      problem = 'Name and code are required.';
    } else if ((latText.isEmpty) != (lonText.isEmpty)) {
      problem = 'Enter both latitude and longitude, or neither.';
    } else if (latText.isNotEmpty && (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180)) {
      problem = 'Latitude must be between -90 and 90, longitude between -180 and 180.';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem), backgroundColor: AppColors.errorText));
      return;
    }

    setState(() => _saving = true);
    try {
      final supabase = Supabase.instance.client;
      final data = {
        'name': name,
        'code': code,
        'address': _address.text.trim(),
        // Empty means "no GPS yet", never 0,0 (that is in the ocean and breaks pricing)
        'latitude': latText.isEmpty ? null : lat,
        'longitude': lonText.isEmpty ? null : lon,
      };
      if (widget.branch == null) {
        final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];
        await supabase.from('branches').insert({...data, 'business_id': businessId, 'status': 'active'});
      } else {
        await supabase.from('branches').update(data).eq('id', widget.branch!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.errorText));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.branch == null ? 'Add branch' : 'Edit ${widget.branch!['name']}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Branch name', hintText: 'e.g. Kitengela'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. KTG'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address (optional)')),
            const SizedBox(height: 20),
            const Text('LOCATION', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.muted)),
            const SizedBox(height: 8),
            TextField(
              controller: _mapsLink,
              onChanged: _readLink,
              decoration: const InputDecoration(
                labelText: 'Paste a Google Maps link (optional)',
                hintText: 'https://www.google.com/maps/…',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            if (_linkHint != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_linkHint!,
                    style: TextStyle(
                        fontSize: 12, color: _linkHint!.startsWith('Location') ? AppColors.successText : AppColors.errorText)),
              ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude', hintText: '-1.2864'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lon,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude', hintText: '36.8172'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('Kenya is around latitude -4 to 4 and longitude 34 to 42.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}
