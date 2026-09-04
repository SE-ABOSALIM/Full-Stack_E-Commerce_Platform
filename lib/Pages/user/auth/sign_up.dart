import 'package:flutter/material.dart';
import 'login.dart';
import '../verification/phone_verification_page.dart';
import '../../../Models/User.dart';
import '../../../Services/api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';
import '../../../Utils/phone_number.dart';

// Tema ve stil sabitleri
class SignUpTheme {
  static const Color primaryColor = Color(0xFF1877F2);
  static const Color backgroundColor = Color(0xFFF8F9FA);
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

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with TickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // Focus nodes for validation
  final FocusNode _nameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _phoneFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _confirmPasswordFocusNode = FocusNode();
  
  // Form validation states
  bool _isNameValid = true;
  bool _isEmailValid = true;
  bool _isPasswordValid = true;
  bool _isConfirmPasswordValid = true;
  bool _isPhoneValid = true;
  
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
        _isNameValid = true; // Focus geri döndüğünde hata mesajını gizle
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

  void _validateName() {
    // Sadece alan boş değilse ve focus kaybedilmişse validation yap
    if (_nameController.text.trim().isNotEmpty) {
      setState(() {
        _isNameValid = _nameController.text.trim().length >= 2;
      });
    }
  }

  void _validateEmail() {
    setState(() {
      _isEmailValid = _emailController.text.trim().isEmpty || _isValidEmail(_emailController.text.trim());
    });
  }

  void _validatePassword() {
    setState(() {
      _isPasswordValid = _passwordController.text.isEmpty || _isValidPassword(_passwordController.text);
    });
    _validateConfirmPassword();
  }

  void _validateConfirmPassword() {
    setState(() {
      _isConfirmPasswordValid = _confirmPasswordController.text.isEmpty || 
                               _passwordController.text == _confirmPasswordController.text;
    });
  }

  void _validatePhone() {
    setState(() {
      _isPhoneValid = _phoneController.text.trim().isEmpty || _isValidPhone(_phoneController.text.trim());
    });
  }

  bool _isFormValid() {
    return _isNameValid && _isEmailValid && _isPasswordValid && 
           _isConfirmPasswordValid && _isPhoneValid &&
           _nameController.text.trim().isNotEmpty &&
           _emailController.text.trim().isNotEmpty &&
           _passwordController.text.isNotEmpty &&
           _confirmPasswordController.text.isNotEmpty &&
           _phoneController.text.trim().isNotEmpty;
  }

  void _handleSignUp() async {
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

    try {
      // Önce telefon doğrulama kodu gönder
      await ApiService.sendVerificationCode(_phoneController.text.trim());
      
      // Doğrulama sayfasına yönlendir
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PhoneVerificationPage(
              phoneNumber: _phoneController.text.trim(),
              userType: 'user',
              userData: {
                'name_surname': _nameController.text.trim(),
                'password': _passwordController.text,
                'email': _emailController.text.trim(),
                'phone_number': _phoneController.text.trim(),
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Kayıt işlemi başarısız';
        
        // Backend'den gelen hata mesajlarını kontrol et
        if (e.toString().contains('Bu telefon numarasına kayıtlı başka bir hesap vardır')) {
          errorMessage = LanguageManager.translate('Bu telefon numarasına kayıtlı başka bir hesap vardır');
        } else if (e.toString().contains('Bu telefon numarası zaten doğrulanmış')) {
          errorMessage = LanguageManager.translate('Bu telefon numarası zaten doğrulanmış');
        } else if (e.toString().contains('detail')) {
          errorMessage = e.toString().replaceAll('Exception: ', '');
        }
        
        CustomDialog.showError(
          context: context,
          title: LanguageManager.translate('Kayıt Başarısız'),
          message: LanguageManager.translate(errorMessage),
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
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SignUpTheme.backgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
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
          },
        ),
        title: Text(
          LanguageManager.translate("Kayıt Ol"),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
            color: Colors.white,
          ),
        ),
        backgroundColor: SignUpTheme.primaryColor,
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
                // Header - kutudan çıkarıldı
                const SizedBox(height: 20),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: SignUpTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: Icon(
                    Icons.person_add,
                    size: 40,
                    color: SignUpTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  LanguageManager.translate("Hesap Oluştur"),
                  style: SignUpTheme.titleStyle.copyWith(fontSize: 28),
                ),
                const SizedBox(height: 8),
                Text(
                  LanguageManager.translate("Bilgilerinizi girerek hesap oluşturun"),
                  style: SignUpTheme.subtitleStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                
                // Form - daha kompakt
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: SignUpTheme.whiteColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                                                 Column(
                           children: [
                                                           _buildTextField(
                                controller: _nameController,
                                hintText: LanguageManager.translate("Ad Soyad"),
                                icon: Icons.person_outline,
                                focusNode: _nameFocusNode,
                                isValid: _isNameValid,
                                errorText: LanguageManager.translate("Ad soyad en az 2 karakter olmalıdır"),
                                onChanged: (_) {
                                  _validateName();
                                  setState(() {});
                                },
                              ),
                             const SizedBox(height: 12),
                                                           _buildTextField(
                                controller: _emailController,
                                hintText: LanguageManager.translate("E-posta"),
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                focusNode: _emailFocusNode,
                                isValid: _isEmailValid,
                                errorText: LanguageManager.translate("Geçerli bir e-posta adresi giriniz"),
                                onChanged: (_) {
                                  _validateEmail();
                                  setState(() {});
                                },
                              ),
                             const SizedBox(height: 12),
                                                           _buildTextField(
                                controller: _phoneController,
                                hintText: LanguageManager.translate("Telefon Numarası"),
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                focusNode: _phoneFocusNode,
                                isValid: _isPhoneValid,
                                errorText: LanguageManager.translate("Geçerli bir telefon numarası giriniz"),
                                onChanged: (_) {
                                  _validatePhone();
                                  setState(() {});
                                },
                              ),
                             const SizedBox(height: 12),
                                                           _buildTextField(
                                controller: _passwordController,
                                hintText: LanguageManager.translate("Şifre"),
                                icon: Icons.lock_outlined,
                                isPassword: true,
                                focusNode: _passwordFocusNode,
                                isValid: _isPasswordValid,
                                errorText: LanguageManager.translate("Şifre en az 8 karakter, bir büyük harf, bir küçük harf ve bir rakam içermelidir"),
                                onChanged: (_) {
                                  _validatePassword();
                                  setState(() {});
                                },
                              ),
                             const SizedBox(height: 12),
                                                           _buildTextField(
                                controller: _confirmPasswordController,
                                hintText: LanguageManager.translate("Şifre Tekrar"),
                                icon: Icons.lock_outlined,
                                isPassword: true,
                                focusNode: _confirmPasswordFocusNode,
                                isValid: _isConfirmPasswordValid,
                                errorText: LanguageManager.translate("Şifreler eşleşmiyor"),
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
                                 onPressed: _isLoading || !_isFormValid() ? null : _handleSignUp,
                                 style: ElevatedButton.styleFrom(
                                   backgroundColor: SignUpTheme.primaryColor,
                                   foregroundColor: SignUpTheme.whiteColor,
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
                                           color: SignUpTheme.whiteColor,
                                           strokeWidth: 2,
                                         ),
                                       )
                                     : Text(
                                         LanguageManager.translate("Kayıt Ol"),
                                         style: SignUpTheme.buttonTextStyle,
                                       ),
                               ),
                             ),
                           ],
                         ),
                         
                         const SizedBox(height: 20),
                         
                         // Giriş yap linki - alta taşındı
                         Row(
                           mainAxisAlignment: MainAxisAlignment.center,
                           children: [
                             Text(
                               LanguageManager.translate("Zaten hesabınız var mı?"),
                               style: SignUpTheme.subtitleStyle,
                             ),
                             GestureDetector(
                               onTap: () {
                                 Navigator.pushReplacement(
                                   context,
                                   PageRouteBuilder(
                                     pageBuilder: (context, animation, secondaryAnimation) => const LoginPage(),
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
                               },
                               child: Text(
                                 LanguageManager.translate("Giriş Yap"),
                                 style: SignUpTheme.linkTextStyle.copyWith(
                                   decoration: TextDecoration.underline,
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
            color: focusNode?.hasFocus == true ? SignUpTheme.whiteColor : SignUpTheme.lightGreyColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isValid ? Colors.transparent : SignUpTheme.errorColor,
              width: 1,
            ),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: isPassword ? (isPassword == _obscurePassword ? _obscurePassword : _obscureConfirmPassword) : false,
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
                color: SignUpTheme.greyColor,
                fontFamily: 'Poppins',
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: SignUpTheme.primaryColor),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        (isPassword == _obscurePassword ? _obscurePassword : _obscureConfirmPassword) 
                            ? Icons.visibility_off 
                            : Icons.visibility,
                        color: SignUpTheme.primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isPassword == _obscurePassword) {
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
                  color: isValid ? SignUpTheme.primaryColor : SignUpTheme.errorColor, 
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
                color: SignUpTheme.errorColor,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
      ],
    );
  }
}
