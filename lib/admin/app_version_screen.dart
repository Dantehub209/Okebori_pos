import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme.dart';

/// Edits the app_version row that tells phones a new APK is available.
class AppVersionScreen extends StatefulWidget {
  const AppVersionScreen({super.key});

  @override
  State<AppVersionScreen> createState() => _AppVersionScreenState();
}

class _AppVersionScreenState extends State<AppVersionScreen> {
  final _latest = TextEditingController();
  final _min = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_latest, _min, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final row = await Supabase.instance.client.from('app_version').select().eq('id', 1).maybeSingle();
      if (row != null) {
        _latest.text = '${row['latest_build']}';
        _min.text = '${row['min_build']}';
        _url.text = row['apk_url'] ?? '';
        _notes.text = row['release_notes'] ?? '';
      }
    } catch (e) {
      _error = 'Could not load the app version. If you have not yet, run supabase/app_version.sql in the Supabase SQL editor.\n\n$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final latest = int.tryParse(_latest.text.trim());
    final min = int.tryParse(_min.text.trim());
    final url = _url.text.trim();
    String? problem;
    if (latest == null || min == null) {
      problem = 'Build numbers must be whole numbers.';
    } else if (min > latest) {
      problem = 'Minimum build cannot be higher than the latest build.';
    } else if (!url.startsWith('https://')) {
      problem = 'The download link must start with https://';
    }
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem), backgroundColor: AppColors.errorText));
      return;
    }

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('app_version').upsert({
        'id': 1,
        'latest_build': latest,
        'min_build': min,
        'apk_url': url,
        'release_notes': _notes.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved. Phones will see the update next time the app opens.'), backgroundColor: AppColors.successText));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.errorText));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(10)),
                    child: Text(_error!, style: const TextStyle(color: AppColors.errorText)),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text(
                          'After building a new APK, upload it, then enter its build number (the number after + in '
                          'pubspec.yaml) and download link here. Phones on an older build get an "Update available" message.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _latest,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Latest build number'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _min,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Minimum build allowed',
                                helperText: 'Older builds must update before they can be used',
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        TextField(controller: _url, decoration: const InputDecoration(labelText: 'APK download link (https://...)')),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(labelText: "What's new (shown to cashiers)"),
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                            child: _saving
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save'),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }
}
