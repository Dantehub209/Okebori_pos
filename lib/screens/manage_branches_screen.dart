import 'package:flutter/material.dart';
import '../theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageBranchesScreen extends StatefulWidget {
  const ManageBranchesScreen({super.key});

  @override
  State<ManageBranchesScreen> createState() => _ManageBranchesScreenState();
}

class _ManageBranchesScreenState extends State<ManageBranchesScreen> {
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client
          .from('branches')
          .select('*')
          .order('name', ascending: true);

      setState(() {
        _branches = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAddBranchDialog() {
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final addressController = TextEditingController();
    final latController = TextEditingController();
    final lonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Branch'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Branch Name *', hintText: 'e.g., Rongai Branch'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Branch Code *', hintText: 'e.g., RONG-01'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address', hintText: 'Physical location'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: latController,
                decoration: const InputDecoration(labelText: 'Latitude', hintText: '-1.2921'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lonController,
                decoration: const InputDecoration(labelText: 'Longitude', hintText: '36.8219'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || codeController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Name and Code are required'), backgroundColor: Colors.orange),
                );
                return;
              }

              try {
                final supabase = Supabase.instance.client;
                final businessId = (await supabase.from('businesses').select('id').single())['id'];

                await supabase.from('branches').insert({
                  'business_id': businessId,
                  'name': nameController.text.trim(),
                  'code': codeController.text.trim().toUpperCase(),
                  'address': addressController.text.trim(),
                  'latitude': latController.text.isNotEmpty ? double.parse(latController.text) : 0.0,
                  'longitude': lonController.text.isNotEmpty ? double.parse(lonController.text) : 0.0,
                  'status': 'active',
                });

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Branch added successfully!'), backgroundColor: Colors.green),
                  );
                  _loadBranches();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Add Branch'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBranchStatus(String branchId, String currentStatus) async {
    try {
      final newStatus = currentStatus == 'active' ? 'inactive' : 'active';
      await Supabase.instance.client
          .from('branches')
          .update({'status': newStatus})
          .eq('id', branchId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Branch ${newStatus == 'active' ? 'activated' : 'deactivated'}')),
      );
      _loadBranches();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Branches'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Branches: ${_branches.length}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _showAddBranchDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Branch'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _branches.length,
                    itemBuilder: (context, index) {
                      final branch = _branches[index];
                      final isActive = branch['status'] == 'active';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isActive ? Colors.green : Colors.grey,
                            child: Icon(Icons.store, color: Colors.white),
                          ),
                          title: Text(branch['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Code: ${branch['code']}'),
                              if (branch['address'] != null && branch['address'].toString().isNotEmpty)
                                Text('Address: ${branch['address']}'),
                              if (branch['latitude'] != null && branch['longitude'] != null)
                                Text('GPS: ${branch['latitude']}, ${branch['longitude']}'),
                            ],
                          ),
                          trailing: Switch(
                            value: isActive,
                            onChanged: (_) => _toggleBranchStatus(branch['id'], branch['status']),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}