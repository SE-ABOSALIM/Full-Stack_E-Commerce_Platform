import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'sign_up.dart';
import 'forgot_password.dart';
import '../home.dart';
import '../cart/my_cart.dart';
import '../../../Models/session.dart';
import '../../../Models/seller_session.dart';
import '../../../Models/User.dart';
import '../../../Services/api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:http/http.dart' as http; // Added for http

// Tema ve stil sabitleri
class AppTheme {
  static const Color primaryColor = Color(0xFF1877F2);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color whiteColor = Colors.white;
  static const Color blackColor = Colors.black;
  static const Color textColor = Color(0xFF1877F2);
  static const Color greyColor = Color(0xFF6C757D);
  static const Color lightGreyColor = Color(0xFFE9ECEF);
  static const Color errorColor = Color(0xFFDC3545);
  
  static const TextStyle appBarTextStyle = TextStyle(
    fontSize: 24,
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: whiteColor,
  );
  
  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: 18,
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w600,
    color: whiteColor,
  );
  
  static const TextStyle signUpTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontFamily: 'Poppins',
    color: primaryColor,
  );

  static const TextStyle forgotPasswordStyle = TextStyle(
    fontSize: 14,
    color: primaryColor,
    fontWeight: FontWeight.w500,
    fontFamily: 'Poppins',
  );

  static const TextStyle titleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    fontFamily: 'Poppins',
    color: blackColor,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 16,
    color: greyColor,
    fontFamily: 'Poppins',
  );
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ticaret Uygulaması',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.primaryColor),
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  final String? infoMessage;
  const LoginPage({super.key, this.infoMessage});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _infoShown = false;
  
  // Focus nodes for validation
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  
  // Validation states
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _animationController.forward();
    
    // Add focus listeners for validation
    _emailFocusNode.addListener(_onEmailFocusChange);
    _passwordFocusNode.addListener(_onPasswordFocusChange);
  }

  void _handleLogin() async {
    if (_usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Lütfen tüm alanları doldurunuz!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final email = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      // Backend API üzerinden login yap
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/users/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: Uri(queryParameters: {
          'email': email,
          'password': password,
        }).query,
      );

      setState(() {
        _isLoading = false;
      });

      if (response.statusCode == 200) {
        final userJson = jsonDecode(response.body);
        final foundUser = User.fromMap(userJson);
        
        // Oturumu başlat
        Session.currentUser = foundUser;
        // Oturum bilgisini kaydet
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        // Guest sepetini kullanıcıya aktar
        await CartManager.mergeGuestCartToUserCart(email);
        // Kullanıcıya özel sepeti yükle
        await CartManager.loadCart();
        
        // Başarı mesajı göster
        CustomDialog.showSuccess(
          context: context,
          title: LanguageManager.translate('Giriş Başarılı'),
          message: LanguageManager.translate('Başarıyla giriş yaptınız!'),
          buttonText: LanguageManager.translate('Tamam'),
          onButtonPressed: () {
            // Direkt ana sayfaya yönlendir
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const HomePage(skipSellerCheck: true),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 500),
              ),
            );
          },
        );
      } else {
        final errorData = jsonDecode(response.body);
        CustomDialog.showError(
          context: context,
          title: LanguageManager.translate('Giriş Başarısız'),
          message: LanguageManager.translate(errorData['detail'] ?? 'E-posta veya şifre hatalı!'),
          buttonText: LanguageManager.translate('Tamam'),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      print('Login error: ${e.runtimeType}');
      if (e.toString().contains('SocketException') || e.toString().contains('Connection refused')) {
        CustomDialog.showError(
          context: context,
          title: LanguageManager.translate('Bağlantı Hatası'),
          message: LanguageManager.translate('Sunucuya bağlanılamıyor. Backend çalışıyor mu?'),
          buttonText: LanguageManager.translate('Tamam'),
        );
      } else {
        CustomDialog.showError(
          context: context,
          title: LanguageManager.translate('Giriş Başarısız'),
          message: LanguageManager.translate('Bir hata oluştu: $e'),
          buttonText: LanguageManager.translate('Tamam'),
        );
      }
    }
  }

  void _onEmailFocusChange() {
    if (!_emailFocusNode.hasFocus && _usernameController.text.trim().isNotEmpty) {
      setState(() {
        _isEmailValid = _isValidEmail(_usernameController.text.trim());
      });
    } else if (_emailFocusNode.hasFocus) {
      setState(() {
        _isEmailValid = true;
      });
    }
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus && _passwordController.text.isNotEmpty) {
      setState(() {
        _isPasswordValid = _passwordController.text.length >= 6;
      });
    } else if (_passwordFocusNode.hasFocus) {
      setState(() {
        _isPasswordValid = true;
      });
    }
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    return emailRegex.hasMatch(email);
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.infoMessage != null && !_infoShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        CustomDialog.showWarning(
          context: context,
          title: LanguageManager.translate('Bilgi'),
          message: widget.infoMessage!,
          buttonText: LanguageManager.translate('Tamam'),
        );
      });
      _infoShown = true;
    }
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () async {
            // Check if seller is logged in
            final seller = await SellerSession.loadSellerSession();
            if (seller != null) {
              // If seller is logged in, navigate to seller panel
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const HomePage(skipSellerCheck: false),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(-1, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            } else {
              // If no seller is logged in, navigate to home page
              Navigator.pushReplacement(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const HomePage(skipSellerCheck: true),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(-1, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                ),
              );
            }
          },
        ),
        title: Text(
          LanguageManager.translate("Giriş Yap"),
          style: AppTheme.appBarTextStyle,
        ),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo ve başlık - kutudan çıkarıldı
                    const SizedBox(height: 20),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Icon(
                        Icons.shopping_cart,
                        size: 50,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      LanguageManager.translate("Hoş Geldiniz"),
                      style: AppTheme.titleStyle.copyWith(fontSize: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      LanguageManager.translate("Hesabınıza giriş yapın"),
                      style: AppTheme.subtitleStyle,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    
                    // Form alanları
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppTheme.whiteColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildTextField(
                            controller: _usernameController,
                            hintText: LanguageManager.translate("E-posta adresiniz"),
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            focusNode: _emailFocusNode,
                            isValid: _isEmailValid,
                            errorText: LanguageManager.translate("Geçerli bir e-posta adresi giriniz"),
                            onChanged: (_) {
                              setState(() {
                                _isEmailValid = _isValidEmail(_usernameController.text.trim());
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          _buildTextField(
                            controller: _passwordController,
                            hintText: LanguageManager.translate("Şifreniz"),
                            icon: Icons.lock_outlined,
                            isPassword: true,
                            focusNode: _passwordFocusNode,
                            isValid: _isPasswordValid,
                            errorText: LanguageManager.translate("Şifre en az 6 karakter olmalıdır"),
                            onChanged: (_) {
                              setState(() {
                                _isPasswordValid = _passwordController.text.length >= 6;
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          
                          // Giriş butonu
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: AppTheme.whiteColor,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: AppTheme.whiteColor,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      LanguageManager.translate("Giriş Yap"),
                                      style: AppTheme.buttonTextStyle,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Şifremi unuttum linki
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const ForgotPasswordPage(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                            transitionDuration: const Duration(milliseconds: 300),
                          ),
                        );
                      },
                      child: Text(
                        LanguageManager.translate("Şifremi Unuttum"),
                        style: AppTheme.forgotPasswordStyle,
                      ),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    // Kayıt ol linki
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.lightGreyColor,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            LanguageManager.translate("Hesabınız yok mu?"),
                            style: AppTheme.subtitleStyle,
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder: (context, animation, secondaryAnimation) => const SignUpPage(),
                                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                    return SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(1, 0),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    );
                                  },
                                  transitionDuration: const Duration(milliseconds: 300),
                                ),
                              );
                            },
                            child: Text(
                              LanguageManager.translate("Kayıt Olun"),
                              style: AppTheme.signUpTextStyle.copyWith(
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    bool isValid = true,
    String? errorText,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: focusNode?.hasFocus == true ? AppTheme.whiteColor : AppTheme.lightGreyColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPassword ? _obscurePassword : false,
            keyboardType: keyboardType,
            style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Poppins',
            ),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: AppTheme.greyColor,
                fontFamily: 'Poppins',
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: AppTheme.primaryColor),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.primaryColor,
                      ),
                      onPressed: _togglePasswordVisibility,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: isValid ? AppTheme.primaryColor : AppTheme.errorColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            ),
          ),
        ),
        if (!isValid && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Text(
              errorText,
              style: TextStyle(
                color: AppTheme.errorColor,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
      ],
    );
  }
}
