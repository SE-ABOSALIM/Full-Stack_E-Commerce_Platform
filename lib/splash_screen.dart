import 'package:flutter/material.dart';
import 'dart:async';
import 'Pages/user/home.dart';
import 'Models/session.dart';
import 'Models/User.dart';
import 'Models/seller_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Services/api_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();

    Timer(const Duration(seconds: 3), () async {
      await _controller.reverse();
      if (mounted) {
        await _restoreUserSession();
        await _restoreSellerSession();
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomePage(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      }
    });
  }

  Future<void> _restoreUserSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      
      if (email != null && email.isNotEmpty) {
        // Fetch users from API and find the user with matching email
        final users = await ApiService.fetchUsers();
        try {
          final userJson = users.firstWhere((u) => u['email'] == email);
          final user = User.fromMap(userJson);
          Session.currentUser = user;
          print('User session restored');
        } catch (e) {
          print('User not found in API, clearing session');
          await prefs.remove('user_email');
          Session.currentUser = null;
        }
      }
    } catch (e) {
      print('Error restoring user session: ${e.runtimeType}');
      Session.currentUser = null;
    }
  }

  Future<void> _restoreSellerSession() async {
    try {
      final seller = await SellerSession.loadSellerSession();
      if (seller != null) {
        print('Seller session restored: ${seller.storeName}');
      }
    } catch (e) {
      print('Error restoring seller session: ${e.runtimeType}');
      await SellerSession.clearSellerSession();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: FadeTransition(
          opacity: _animation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.asset(
                  'assets/App-Logo.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 18),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF28518)),
                  backgroundColor: Color(0xFFE3EAF2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 