import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared by the phone app (main.dart) and the web admin (admin/admin_main.dart).
Future<void> initSupabase() => Supabase.initialize(
      url: 'https://elwscqcwgsleiifgjwzr.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVsd3NjcWN3Z3NsZWlpZmdqd3pyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxOTQ1NTEsImV4cCI6MjEwMjc3MDU1MX0.1F9pkxWmyf_ye9M5NZ6ja6yHTUKoLvvEGGfoKo1ibh8',
    );
