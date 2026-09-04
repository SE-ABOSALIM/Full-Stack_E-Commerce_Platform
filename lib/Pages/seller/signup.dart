import 'package:flutter/material.dart';
import 'login.dart';
import '../../Services/seller_api_service.dart';
import '../user/verification/phone_verification_page.dart';
import '../../Widgets/custom_dialog.dart';
import '../../Utils/language_manager.dart';
import '../../Utils/phone_number.dart';

// Tema ve stil sabitleri
class SellerSignupTheme {
  static const Color primaryColor = Color(0xFF1877F2);
  static const Color backgroundColor = Color(0xFF1877F2);
  static const Color whiteColor = Colors.white;
  static const Color blackColor = Colors.black;
  static const Color greyColor = Color(0xFF6C757D);
  static const Color lightGreyColor = Color(0xFFE9ECEF);
  static const Color errorColor = Color(0xFFDC3545);
  static const Color successColor = Color(0xFF28A745);
  
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

  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: 18,
    fontFamily: 'Poppins',
    fontWeight: FontWeight.w600,
    color: whiteColor,
  );

  static const TextStyle linkTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    fontFamily: 'Poppins',
    color: primaryColor,
  );
}

class SellerSignupPage extends StatefulWidget {
  const SellerSignupPage({super.key});

  @override
  State<SellerSignupPage> createState() => _SellerSignupPageState();
}

class _SellerSignupPageState extends State<SellerSignupPage> with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _storeNameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // Focus nodes for validation
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  final FocusNode _storeNameFocusNode = FocusNode();
  
  // Form validation states
  bool _isNameValid = true;
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  bool _isConfirmPasswordValid = true;
  bool _isPhoneValid = true;
  bool _isStoreNameValid = true;
  
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
    _nameFocusNode.addListener(_onNameFocusChange);
    _emailFocusNode.addListener(_onEmailFocusChange);
    _phoneFocusNode.addListener(_onPhoneFocusChange);
    _passwordFocusNode.addListener(_onPasswordFocusChange);
    _confirmPasswordFocusNode.addListener(_onConfirmPasswordFocusChange);
    _storeNameFocusNode.addListener(_onStoreNameFocusChange);
  }

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    return emailRegex.hasMatch(email);
  }

  bool _isValidPassword(String password) {
    final passwordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}');
    return passwordRegex.hasMatch(password);
  }

  bool _isValidPhone(String phone) {
    return isValidPhoneNumber(phone);
  }

  void _onNameFocusChange() {
    if (!_nameFocusNode.hasFocus && _nameController.text.trim().isNotEmpty) {
      setState(() {
        _isNameValid = _nameController.text.trim().length >= 2;
      });
    } else if (_nameFocusNode.hasFocus) {
      setState(() {
        _isNameValid = true;
      });
    }
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

  void _onPhoneFocusChange() {
    if (!_phoneFocusNode.hasFocus && _phoneController.text.trim().isNotEmpty) {
      setState(() {
        _isPhoneValid = _isValidPhone(_phoneController.text.trim());
      });
    } else if (_phoneFocusNode.hasFocus) {
      setState(() {
        _isPhoneValid = true;
      });
    }
  }

  void _onPasswordFocusChange() {
    if (!_passwordFocusNode.hasFocus && _passwordController.text.isNotEmpty) {
      setState(() {
        _isPasswordValid = _isValidPassword(_passwordController.text);
      });
      _validateConfirmPassword();
    } else if (_passwordFocusNode.hasFocus) {
      setState(() {
        _isPasswordValid = true;
      });
    }
  }

  void _onConfirmPasswordFocusChange() {
    if (!_confirmPasswordFocusNode.hasFocus && _confirmPasswordController.text.isNotEmpty) {
      setState(() {
        _isConfirmPasswordValid = _passwordController.text == _confirmPasswordController.text;
      });
    } else if (_confirmPasswordFocusNode.hasFocus) {
      setState(() {
        _isConfirmPasswordValid = true;
      });
    }
  }

  void _onStoreNameFocusChange() {
    if (!_storeNameFocusNode.hasFocus && _storeNameController.text.trim().isNotEmpty) {
      setState(() {
        _isStoreNameValid = _storeNameController.text.trim().length >= 2;
      });
    } else if (_storeNameFocusNode.hasFocus) {
      setState(() {
        _isStoreNameValid = true;
      });
    }
  }

  void _validateName() {
    setState(() {
      _isNameValid = _nameController.text.trim().length >= 2;
    });
  }

  void _validateEmail() {
    setState(() {
      _isEmailValid = _isValidEmail(_emailController.text.trim());
    });
  }

  void _validatePhone() {
    setState(() {
      _isPhoneValid = _isValidPhone(_phoneController.text.trim());
    });
  }

  void _validateStoreName() {
    setState(() {
      _isStoreNameValid = _storeNameController.text.trim().length >= 2;
    });
  }

  void _validatePassword() {
    setState(() {
      _isPasswordValid = _isValidPassword(_passwordController.text);
    });
    _validateConfirmPassword();
  }

  void _validateConfirmPassword() {
    setState(() {
      _isConfirmPasswordValid = _confirmPasswordController.text.isEmpty || 
                               _passwordController.text == _confirmPasswordController.text;
    });
  }

  bool _isFormValid() {
    return _isNameValid && _isEmailValid && _isPasswordValid && 
           _isConfirmPasswordValid && _isPhoneValid && _isStoreNameValid &&
           _nameController.text.trim().isNotEmpty &&
           _emailController.text.trim().isNotEmpty &&
           _passwordController.text.isNotEmpty &&
           _confirmPasswordController.text.isNotEmpty &&
           _phoneController.text.trim().isNotEmpty &&
           _storeNameController.text.trim().isNotEmpty;
  }

  Future<void> _signup() async {
    if (!_isFormValid()) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Form Hatası'),
        message: LanguageManager.translate('Lütfen tüm alanları doğru şekilde doldurunuz!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Şifreler eşleşmiyor!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    if (!_isValidEmail(_emailController.text.trim())) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Geçerli bir e-posta adresi giriniz!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    if (!_isValidPassword(_passwordController.text)) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Şifre en az 8 karakter, bir büyük harf, bir küçük harf ve bir rakam içermelidir!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    if (!_isValidPhone(_phoneController.text.trim())) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Geçerli bir telefon numarası giriniz'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Önce telefon doğrulama kodu gönder (seller için)
      await SellerApiService.sendSellerVerificationCode(_phoneController.text);
      
      // Doğrulama sayfasına yönlendir
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PhoneVerificationPage(
              phoneNumber: _phoneController.text,
              userType: 'seller',
              userData: {
                'name': _nameController.text,
                'email': _emailController.text,
                'password': _passwordController.text,
                'phone': _phoneController.text,
                'store_name': _storeNameController.text,
                'cargo_company': 'Araskargo',
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        CustomDialog.showError(
          context: context,
                  title: LanguageManager.translate('Kayıt Başarısız'),
        message: LanguageManager.translate('Bu telefon numarası zaten kullanımda olabilir. Lütfen farklı bir telefon numarası deneyin.'),
        buttonText: LanguageManager.translate('Tamam'),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _storeNameController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _storeNameFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SellerSignupTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          LanguageManager.translate('Satıcı Kaydı'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
            color: Colors.white,
          ),
        ),
        backgroundColor: SellerSignupTheme.primaryColor,
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
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                                 // Header
                 const SizedBox(height: 20),
                 Container(
                   width: 80,
                   height: 80,
                   decoration: BoxDecoration(
                     color: Colors.white.withOpacity(0.2),
                     borderRadius: BorderRadius.circular(40),
                   ),
                   child: Icon(
                     Icons.store,
                     size: 40,
                     color: Colors.white,
                   ),
                 ),
                 const SizedBox(height: 16),
                 Text(
                   LanguageManager.translate('Satıcı Hesabı Oluştur'),
                   style: SellerSignupTheme.titleStyle.copyWith(fontSize: 28, color: Colors.white),
                 ),
                const SizedBox(height: 8),
                const SizedBox(height: 20),
                
                                 // Form - scrollable
                 Expanded(
                   child: SingleChildScrollView(
                     child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: SellerSignupTheme.whiteColor,
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
                        Column(
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              hintText: LanguageManager.translate('Ad Soyad'),
                              icon: Icons.person_outline,
                              focusNode: _nameFocusNode,
                              isValid: _isNameValid,
                              errorText: LanguageManager.translate('Ad soyad en az 2 karakter olmalıdır'),
                              onChanged: (_) {
                                _validateName();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _emailController,
                              hintText: LanguageManager.translate('E-posta'),
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              focusNode: _emailFocusNode,
                              isValid: _isEmailValid,
                              errorText: LanguageManager.translate('Geçerli bir e-posta adresi giriniz'),
                              onChanged: (_) {
                                _validateEmail();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _phoneController,
                              hintText: LanguageManager.translate('Telefon Numarası'),
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              focusNode: _phoneFocusNode,
                              isValid: _isPhoneValid,
                              errorText: LanguageManager.translate('Geçerli bir telefon numarası giriniz'),
                              onChanged: (_) {
                                _validatePhone();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _storeNameController,
                              hintText: LanguageManager.translate('Mağaza Adı'),
                              icon: Icons.store_outlined,
                              focusNode: _storeNameFocusNode,
                              isValid: _isStoreNameValid,
                              errorText: LanguageManager.translate('Mağaza adı en az 2 karakter olmalıdır'),
                              onChanged: (_) {
                                _validateStoreName();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _passwordController,
                              hintText: LanguageManager.translate('Şifre'),
                              icon: Icons.lock_outlined,
                              isPassword: true,
                              focusNode: _passwordFocusNode,
                              isValid: _isPasswordValid,
                              errorText: LanguageManager.translate('Şifre en az 8 karakter, bir büyük harf, bir küçük harf ve bir rakam içermelidir'),
                              onChanged: (_) {
                                _validatePassword();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              controller: _confirmPasswordController,
                              hintText: LanguageManager.translate('Şifre Tekrar'),
                              icon: Icons.lock_outlined,
                              isPassword: true,
                              focusNode: _confirmPasswordFocusNode,
                              isValid: _isConfirmPasswordValid,
                              errorText: LanguageManager.translate('Şifreler eşleşmiyor'),
                              onChanged: (_) {
                                _validateConfirmPassword();
                                setState(() {});
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Kayıt ol butonu - yukarı taşındı
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading || !_isFormValid() ? null : _signup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SellerSignupTheme.primaryColor,
                                  foregroundColor: SellerSignupTheme.whiteColor,
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
                                          color: SellerSignupTheme.whiteColor,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        LanguageManager.translate('Kayıt Ol'),
                                        style: SellerSignupTheme.buttonTextStyle,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Giriş yap linki - beyaz container dışına taşındı
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      LanguageManager.translate('Zaten hesabınız var mı?'),
                      style: SellerSignupTheme.subtitleStyle.copyWith(color: Colors.white),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SellerLoginPage(),
                          ),
                        );
                      },
                      child: Text(
                        LanguageManager.translate('Giriş Yap'),
                        style: SellerSignupTheme.linkTextStyle.copyWith(
                          decoration: TextDecoration.underline,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
    int? maxLength,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: focusNode?.hasFocus == true ? SellerSignupTheme.whiteColor : SellerSignupTheme.lightGreyColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isValid ? Colors.transparent : SellerSignupTheme.errorColor,
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPassword ? (controller == _passwordController ? _obscurePassword : _obscureConfirmPassword) : false,
            keyboardType: keyboardType,
            maxLength: maxLength,
            style: const TextStyle(
              fontSize: 16,
              fontFamily: 'Poppins',
            ),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                color: SellerSignupTheme.greyColor,
                fontFamily: 'Poppins',
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: SellerSignupTheme.primaryColor),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        (controller == _passwordController ? _obscurePassword : _obscureConfirmPassword) 
                            ? Icons.visibility_off 
                            : Icons.visibility,
                        color: SellerSignupTheme.primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          if (controller == _passwordController) {
                            _obscurePassword = !_obscurePassword;
                          } else {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          }
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color: isValid ? SellerSignupTheme.primaryColor : SellerSignupTheme.errorColor, 
                  width: 2
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              counterText: "",
            ),
          ),
        ),
        if (!isValid && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Text(
              errorText,
              style: TextStyle(
                color: SellerSignupTheme.errorColor,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
      ],
    );
  }
}
