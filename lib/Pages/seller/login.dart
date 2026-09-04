import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'signup.dart';
import '../../Models/seller_session.dart';
import '../../Services/seller_api_service.dart';
import '../../Widgets/custom_dialog.dart';
import '../../Utils/language_manager.dart';

// Tema ve stil sabitleri
class SellerLoginTheme {
  static const Color primaryColor = Color(0xFF1877F2);
  static const Color backgroundColor = Color(0xFF1877F2);
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

class SellerLoginPage extends StatefulWidget {
  const SellerLoginPage({super.key});

  @override
  State<SellerLoginPage> createState() => _SellerLoginPageState();
}

class _SellerLoginPageState extends State<SellerLoginPage> with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  // Focus nodes for validation
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  
  // Validation states
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  
  // Animation controllers
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

  void _onEmailFocusChange() {
    if (!_emailFocusNode.hasFocus && _emailController.text.trim().isNotEmpty) {
      setState(() {
        _isEmailValid = _isValidEmail(_emailController.text.trim());
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

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
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

    try {
      print('Checking backend status...');
      final isBackendRunning = await SellerApiService.checkBackendStatus();
      
      if (!isBackendRunning) {
        throw Exception('Backend çalışmıyor. Lütfen backend\'i başlatın.');
      }
      
      print('Starting login process...');
      final seller = await SellerApiService.login(
        _emailController.text,
        _passwordController.text,
      );
      
      // Seller session'ına kaydet
      await SellerSession.saveSellerSession(seller);
      print('Seller session saved');
      
      print('Login successful, navigating to dashboard...');
      if (mounted) {
        // Direkt dashboard'a yönlendir
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SellerDashboardPage(seller: seller),
          ),
        );
      }
    } catch (e) {
      print('Login error in UI: ${e.runtimeType}');
      if (mounted) {
        CustomDialog.showError(
          context: context,
                  title: LanguageManager.translate('Giriş Başarısız'),
        message: LanguageManager.translate('E-posta veya şifre hatalı!'),
        buttonText: LanguageManager.translate('Tamam'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SellerLoginTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          LanguageManager.translate("Satıcı Girişi"),
          style: SellerLoginTheme.appBarTextStyle,
        ),
        backgroundColor: SellerLoginTheme.primaryColor,
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
                     Container(
                       width: 100,
                       height: 100,
                       decoration: BoxDecoration(
                         color: Colors.white.withOpacity(0.2),
                         borderRadius: BorderRadius.circular(50),
                       ),
                       child: Icon(
                         Icons.store,
                         size: 50,
                         color: Colors.white,
                       ),
                     ),
                     const SizedBox(height: 16),
                     Text(
                       LanguageManager.translate("Hoş Geldiniz"),
                       style: SellerLoginTheme.titleStyle.copyWith(fontSize: 28, color: Colors.white),
                     ),
                    const SizedBox(height: 30),
                    
                    // Form alanları
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: SellerLoginTheme.whiteColor,
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
                            controller: _emailController,
                            hintText: LanguageManager.translate("E-posta adresiniz"),
                            icon: Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            focusNode: _emailFocusNode,
                            isValid: _isEmailValid,
                            errorText: LanguageManager.translate("Geçerli bir e-posta adresi giriniz"),
                            onChanged: (_) {
                              setState(() {
                                _isEmailValid = _isValidEmail(_emailController.text.trim());
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
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SellerLoginTheme.primaryColor,
                                foregroundColor: SellerLoginTheme.whiteColor,
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
                                        color: SellerLoginTheme.whiteColor,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      LanguageManager.translate("Giriş Yap"),
                                      style: SellerLoginTheme.buttonTextStyle,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 70),
                    
                                         // Kayıt ol linki
                     Container(
                       padding: const EdgeInsets.all(20),
                       decoration: BoxDecoration(
                         color: Colors.white.withOpacity(0.2),
                         borderRadius: BorderRadius.circular(15),
                       ),
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.center,
                         children: [
                           Text(
                             LanguageManager.translate("Hesabınız yok mu?"),
                             style: SellerLoginTheme.subtitleStyle.copyWith(color: Colors.white),
                           ),
                          GestureDetector(
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const SellerSignupPage(),
                                ),
                              );
                            },
                                                         child: Text(
                               LanguageManager.translate("Kayıt Olun"),
                               style: SellerLoginTheme.signUpTextStyle.copyWith(
                                 decoration: TextDecoration.underline,
                                 color: Colors.white,
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
            color: focusNode?.hasFocus == true ? SellerLoginTheme.whiteColor : SellerLoginTheme.lightGreyColor,
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
                color: SellerLoginTheme.greyColor,
                fontFamily: 'Poppins',
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: SellerLoginTheme.primaryColor),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: SellerLoginTheme.primaryColor,
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
                  color: isValid ? SellerLoginTheme.primaryColor : SellerLoginTheme.errorColor,
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
                color: SellerLoginTheme.errorColor,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
      ],
    );
  }
} 