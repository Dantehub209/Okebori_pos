import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterUserScreen extends StatefulWidget {
  const RegisterUserScreen({super.key});

  @override
  State<RegisterUserScreen> createState() => _RegisterUserScreenState();
}

class _RegisterUserScreenState extends State<RegisterUserScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String? _selectedRoleId;
  String? _selectedBranchId;
  bool _isLoading = false;
  bool _isDataLoading = true;

  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isDataLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      
      final roles = await supabase.from('roles').select('id, name');
      final branches = await supabase.from('branches').select('id, name').eq('status', 'active');
      
      setState(() {
        _roles = List<Map<String, dynamic>>.from(roles);
        _branches = List<Map<String, dynamic>>.from(branches);
        _isDataLoading = false;
      });
    } catch (e) {
      setState(() {
        _isDataLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load options: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _registerUser() async {
    if (_nameController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields. Password must be 6+ chars.'), backgroundColor: Colors.orange)
      );
      return;
    }
    if (_selectedRoleId == null || _selectedBranchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Role and Branch.'), backgroundColor: Colors.orange)
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      final authResponse = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (authResponse.user == null) throw Exception("Failed to create auth user");
      final authUserId = authResponse.user!.id;

      final businessId = (await supabase.from('businesses').select('id').limit(1).single())['id'];

      await supabase.from('users').insert({
        'id': authUserId,
        'business_id': businessId,
        'branch_id': _selectedBranchId,
        'role_id': _selectedRoleId,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'status': 'active',
      });

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User Registered Successfully!'), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDataLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register New User'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_roles.isEmpty || _branches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Register New User'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Could not load Roles or Branches.', style: TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadOptions, child: Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Register New User'), backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 16),
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email Address *', prefixIcon: Icon(Icons.email)), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone)), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password (Min 6 chars) *', prefixIcon: Icon(Icons.lock)), obscureText: true),
            const SizedBox(height: 24),
            
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Assign Role *', border: OutlineInputBorder()),
              value: _selectedRoleId,
              items: _roles.map((r) => DropdownMenuItem(value: r['id'].toString(), child: Text(r['name']))).toList(),
              onChanged: (v) => setState(() => _selectedRoleId = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Assign Branch *', border: OutlineInputBorder()),
              value: _selectedBranchId,
              items: _branches.map((b) => DropdownMenuItem(value: b['id'].toString(), child: Text(b['name']))).toList(),
              onChanged: (v) => setState(() => _selectedBranchId = v),
            ),

            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _registerUser,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white) 
                    : Text('Create User', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}