import 'package:flutter/material.dart';
import '../Models/User.dart';
import '../Services/api_service.dart';

class TestUsersPage extends StatefulWidget {
  const TestUsersPage({super.key});

  @override
  State<TestUsersPage> createState() => _TestUsersPageState();
}

class _TestUsersPageState extends State<TestUsersPage> {
  List<User> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final allUsers = await ApiService.fetchUsers();
    setState(() {
      users = allUsers.map((e) => User.fromMap(e)).toList();
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
            'Kayıtlı Kullanıcılar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            fontFamily: 'Roboto',
          ),
        ),
        backgroundColor: const Color(0xFF1877F2),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1877F2),
                      child: Text(
                        user.nameSurname[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text('${user.nameSurname} (ID: ${user.id ?? "-"})'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Email: ${user.email}'),
                        Text('Telefon: ${user.phoneNumber}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        await ApiService.deleteUser(user.id!);
                        _loadUsers();
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadUsers,
        backgroundColor: const Color(0xFF1877F2),
        child: const Icon(
            Icons.refresh,
            color: Colors.white,
        ),
      ),
    );
  }
}
