import 'package:flutter/material.dart';
import 'login.dart';
import '../../../Services/api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';

// Tema ve stil sabitleri
class ForgotPasswordTheme {
  static const Color primaryColor = Color(0xFF1877F2);
  static const Color backgroundColor = Color(0xFFF8F9FA);
  static const Color whiteColor = Colors.white;
  static const Color blackColor = Colors.black;
  static const Color greyColor = Color(0xFF6C757D);
  static const Color lightGreyColor = Color(0xFFE9ECEF);
  static const Color errorColor = Color(0xFFDC3545);
  static const Color successColor = Color(0xFF28A745);

  static const TextStyle titleStyle = TextStyle(
    fontSize: 28,
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

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _phoneFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _codeSent = false;
  bool _busy = false;
  bool _sendingCode = false;
  bool _obscurePassword = true;
  String? _message;
  String? _phoneError;
  String? _codeError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    for (final focus in [_phoneFocus, _codeFocus, _passwordFocus]) {
      focus.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  void _showError(String message) {
    CustomDialog.showError(
      context: context,
      title: LanguageManager.translate('Hata'),
      message: LanguageManager.translate(message),
      buttonText: LanguageManager.translate('Tamam'),
    );
  }

  Future<void> _requestCode() async {
    if (_phone.text.trim().isEmpty) {
      setState(() {
        _phoneError = LanguageManager.translate('Telefon numaranızı girin.');
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _sendingCode = true;
      _phoneError = null;
      _message = null;
    });
    try {
      await ApiService.requestPasswordReset(_phone.text.trim());
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _message =
            'Hesap bulunursa telefonunuza kod gönderilir. Kod 5 dakika geçerlidir. Yeni kod istemeden önce 60 saniye bekleyin.';
      });
    } catch (_) {
      if (mounted) {
        _showError(
          'Kod gönderilemedi. Telefon numaranızı kontrol edip tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sendingCode = false;
        });
      }
    }
  }

  Future<void> _reset() async {
    setState(() {
      _codeError =
          RegExp(r'^[0-9]{6}$').hasMatch(_code.text.trim())
              ? null
              : LanguageManager.translate('6 haneli doğrulama kodunu girin.');
      _passwordError =
          _password.text.length >= 8
              ? null
              : LanguageManager.translate('Şifre en az 8 karakter olmalıdır.');
    });
    if (_codeError != null || _passwordError != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ApiService.resetPassword(
        _phone.text.trim(),
        _code.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      _code.clear();
      _password.clear();
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: LanguageManager.translate(
          'Şifreniz değiştirildi. Yeni şifrenizle giriş yapabilirsiniz.',
        ),
        buttonText: LanguageManager.translate('Giriş Yap'),
        onButtonPressed:
            () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
      );
    } catch (_) {
      if (mounted) {
        _showError(
          'Kod geçersiz, süresi dolmuş veya deneme sınırına ulaşılmış. Yeni kod isteyin.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _phoneFocus.dispose();
    _codeFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ForgotPasswordTheme.backgroundColor,
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Şifre Sıfırlama'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        backgroundColor: ForgotPasswordTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: ForgotPasswordTheme.primaryColor.withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: const Icon(
                  Icons.lock_reset,
                  size: 40,
                  color: ForgotPasswordTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              LanguageManager.translate('Şifre Sıfırlama'),
              style: ForgotPasswordTheme.titleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              LanguageManager.translate(
                'Telefonunuza gönderilen kodla yeni şifrenizi belirleyin.',
              ),
              style: ForgotPasswordTheme.subtitleStyle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: ForgotPasswordTheme.whiteColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAuthField(
                    fieldKey: const Key('reset-phone'),
                    controller: _phone,
                    focus: _phoneFocus,
                    hint: 'Telefon Numarası',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    error: _phoneError,
                    onChanged:
                        (_) => setState(() {
                          _codeSent = false;
                          _message = null;
                          _phoneError = null;
                          _code.clear();
                        }),
                  ),
                  const SizedBox(height: 20),
                  _buildAction(
                    _codeSent ? 'Yeni Kod Gönder' : 'Kod Gönder',
                    _requestCode,
                    loading: _busy && _sendingCode,
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ForgotPasswordTheme.primaryColor.withValues(
                          alpha: 0.06,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: ForgotPasswordTheme.primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LanguageManager.translate(_message!),
                              style: ForgotPasswordTheme.subtitleStyle.copyWith(
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_codeSent) ...[
                    const SizedBox(height: 20),
                    _buildAuthField(
                      fieldKey: const Key('reset-code'),
                      controller: _code,
                      focus: _codeFocus,
                      hint: 'Doğrulama Kodu',
                      icon: Icons.pin_outlined,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      error: _codeError,
                      onChanged:
                          (_) => setState(() {
                            _codeError = null;
                          }),
                    ),
                    const SizedBox(height: 20),
                    _buildAuthField(
                      fieldKey: const Key('reset-password'),
                      controller: _password,
                      focus: _passwordFocus,
                      hint: 'Yeni Şifre',
                      icon: Icons.lock_outlined,
                      password: true,
                      error: _passwordError,
                      onChanged:
                          (_) => setState(() {
                            _passwordError = null;
                          }),
                    ),
                    const SizedBox(height: 20),
                    _buildAction(
                      'Şifreyi Sıfırla',
                      _reset,
                      loading: _busy && !_sendingCode,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed:
                  _busy
                      ? null
                      : () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                      ),
              child: Text(
                LanguageManager.translate('Giriş Yap'),
                style: ForgotPasswordTheme.linkTextStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Match the existing user login form: filled grey fields, blue focus, Poppins,
  // 15px corners and 50px buttons. Account Information keeps its own card style.
  Widget _buildAuthField({
    required Key fieldKey,
    required TextEditingController controller,
    required FocusNode focus,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool password = false,
    int? maxLength,
    String? error,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color:
                focus.hasFocus
                    ? ForgotPasswordTheme.whiteColor
                    : ForgotPasswordTheme.lightGreyColor,
            borderRadius: BorderRadius.circular(15),
          ),
          child: TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focus,
            enabled: !_busy,
            obscureText: password && _obscurePassword,
            autocorrect: !password,
            enableSuggestions: !password,
            keyboardType: keyboardType,
            maxLength: maxLength,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 16, fontFamily: 'Poppins'),
            decoration: InputDecoration(
              hintText: LanguageManager.translate(hint),
              counterText: '',
              hintStyle: const TextStyle(
                color: ForgotPasswordTheme.greyColor,
                fontFamily: 'Poppins',
              ),
              filled: true,
              fillColor: Colors.transparent,
              prefixIcon: Icon(icon, color: ForgotPasswordTheme.primaryColor),
              suffixIcon:
                  password
                      ? IconButton(
                        tooltip: LanguageManager.translate(
                          _obscurePassword ? 'Şifreyi göster' : 'Şifreyi gizle',
                        ),
                        onPressed:
                            _busy
                                ? null
                                : () => setState(() {
                                  _obscurePassword = !_obscurePassword;
                                }),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: ForgotPasswordTheme.primaryColor,
                        ),
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide:
                    error == null
                        ? BorderSide.none
                        : const BorderSide(
                          color: ForgotPasswordTheme.errorColor,
                        ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide(
                  color:
                      error == null
                          ? ForgotPasswordTheme.primaryColor
                          : ForgotPasswordTheme.errorColor,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 15,
                horizontal: 20,
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12),
            child: Text(
              error,
              style: const TextStyle(
                color: ForgotPasswordTheme.errorColor,
                fontSize: 12,
                fontFamily: 'Poppins',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAction(
    String label,
    VoidCallback onPressed, {
    required bool loading,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ForgotPasswordTheme.primaryColor,
          foregroundColor: ForgotPasswordTheme.whiteColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child:
            loading
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : Text(
                  LanguageManager.translate(label),
                  style: ForgotPasswordTheme.buttonTextStyle,
                ),
      ),
    );
  }
}
