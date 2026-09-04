import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../Services/api_service.dart';
import '../../../Services/seller_api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';

class PhoneVerificationPage extends StatefulWidget {
  final String phoneNumber;
  final String userType; // 'user' veya 'seller'
  final Map<String, dynamic> userData; // Kayıt verileri
  final bool isRegistration;
  
  const PhoneVerificationPage({
    super.key,
    required this.phoneNumber,
    required this.userType,
    required this.userData,
    this.isRegistration = true,
  });

  @override
  State<PhoneVerificationPage> createState() => _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends State<PhoneVerificationPage>
    with TickerProviderStateMixin {
  final List<TextEditingController> _codeControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );
  
  bool _isLoading = false;
  bool _isResending = false;
  bool _isRegistrationCompleted = false; // Kayıt tamamlandı mı kontrolü
  int _countdown = 0;
  Timer? _timer;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _startCountdown();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    for (var controller in _codeControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _countdown = 60; // 60 saniye
    });
    
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_countdown > 0) {
            _countdown--;
          } else {
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  String _maskPhoneNumber(String phoneNumber) {
    if (phoneNumber.length <= 2) return phoneNumber;
    return '${'*' * (phoneNumber.length - 2)}${phoneNumber.substring(phoneNumber.length - 2)}';
  }

  void _onCodeChanged(String value, int index) {
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    
    // Tüm kodlar girildi mi kontrol et ve kayıt tamamlanmamışsa doğrula
    if (_codeControllers.every((controller) => controller.text.isNotEmpty) && !_isRegistrationCompleted) {
      _verifyCode();
    }
  }

  Future<void> _verifyCode() async {
    // Eğer kayıt zaten tamamlandıysa işlemi durdur
    if (_isRegistrationCompleted) {
      return;
    }

    final verificationCode = _codeControllers
        .map((controller) => controller.text)
        .join();
    
    if (verificationCode.length != 6) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      print('DEBUG: Telefon verification başlatılıyor...');
      print('DEBUG: User type: ${widget.userType}');
      
      final response = widget.userType == 'seller' 
          ? await SellerApiService.verifySellerPhone(widget.phoneNumber, verificationCode)
          : await ApiService.verifyPhone(widget.phoneNumber, verificationCode);

      if (response['success'] == true) {
        if (!widget.isRegistration) {
          _isRegistrationCompleted = true;
          if (mounted) Navigator.of(context).pop();
          return;
        }
        // Telefon doğrulandı, şimdi kayıt işlemini tamamla
        await _completeRegistration();
      } else {
        if (mounted) {
          CustomDialog.showError(
            context: context,
            title: 'Doğrulama Hatası',
            message: response['message'] ?? 'Kod doğrulanamadı',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomDialog.showError(
          context: context,
          title: 'Hata',
          message: 'Kod doğrulanırken bir hata oluştu: $e',
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

  Future<void> _completeRegistration() async {
    // Eğer kayıt zaten tamamlandıysa işlemi durdur
    if (_isRegistrationCompleted) {
      return;
    }

    try {
      if (widget.userType == 'user') {
        // Kullanıcı kaydını tamamla
        await ApiService.registerUser(widget.userData);
        
        // Kayıt tamamlandı olarak işaretle
        _isRegistrationCompleted = true;
        
        // Backend başarılı response döndürdüyse başarılı kabul et
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
          CustomDialog.showSuccess(
            context: context,
            title: 'Başarılı',
            message: 'Hesabınız başarıyla oluşturuldu! Giriş yapabilirsiniz.',
          );
        }
      } else {
        // Satıcı kaydını tamamla
        await SellerApiService.signup(
          name: widget.userData['name'],
          email: widget.userData['email'],
          password: widget.userData['password'],
          phone: widget.userData['phone'],
          storeName: widget.userData['store_name'],
          cargoCompany: widget.userData['cargo_company'],
        );
        
        // Kayıt tamamlandı olarak işaretle
        _isRegistrationCompleted = true;
        
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/seller/login');
          CustomDialog.showSuccess(
            context: context,
            title: 'Başarılı',
            message: 'Satıcı hesabınız başarıyla oluşturuldu! Giriş yapabilirsiniz.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Hesap oluşturulurken bir hata oluştu';
        
        // Backend'den gelen hata mesajlarını kontrol et
        if (e.toString().contains('Email already registered')) {
          errorMessage = 'Bu telefon numarası zaten kullanımda. Lütfen farklı bir telefon numarası deneyin.';
        } else if (e.toString().contains('Bu telefon numarasına kayıtlı başka bir hesap vardır')) {
          errorMessage = LanguageManager.translate('Bu telefon numarasına kayıtlı başka bir hesap vardır');
        } else if (e.toString().contains('detail')) {
          // Backend'den gelen detay mesajını al
          errorMessage = e.toString().replaceAll('Exception: ', '');
        }
        
        CustomDialog.showError(
          context: context,
          title: 'Kayıt Hatası',
          message: errorMessage,
        );
      }
    }
  }

  Future<void> _resendCode() async {
    if (_countdown > 0) return;

    setState(() {
      _isResending = true;
    });

    try {
      final response = widget.userType == 'seller'
          ? await SellerApiService.sendSellerVerificationCode(widget.phoneNumber)
          : await ApiService.sendVerificationCode(widget.phoneNumber);

      if (response['success'] == true) {
        if (mounted) {
          _startCountdown();
          CustomDialog.showSuccess(
            context: context,
            title: 'Kod Gönderildi',
            message: 'Yeni doğrulama kodu telefonunuza gönderildi.',
          );
        }
      } else {
        if (mounted) {
          CustomDialog.showError(
            context: context,
            title: 'Hata',
            message: response['message'] ?? 'Kod gönderilemedi',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = 'Kod gönderilirken bir hata oluştu';
        
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
          title: 'Hata',
          message: errorMessage,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

    @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Telefon Doğrulama',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 40),
            
            // Basit telefon ikonu
            Icon(
              Icons.phone_android,
              size: 60,
              color: const Color(0xFF1877F2),
            ),
            
            const SizedBox(height: 30),
            
            // Başlık
            const Text(
              'Doğrulama Kodu',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            
            const SizedBox(height: 10),
            
            // Açıklama
            Text(
              '${_maskPhoneNumber(widget.phoneNumber)} numarasına kod gönderildi',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 40),
            
            // Basit kod girişi
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(6, (index) {
                return Container(
                  width: 45,
                  height: 55,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _focusNodes[index].hasFocus
                          ? const Color(0xFF1877F2)
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _codeControllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(1),
                    ],
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) => _onCodeChanged(value, index),
                  ),
                );
              }),
            ),
            
            const SizedBox(height: 40),
            
            // Doğrula butonu
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isLoading || _isRegistrationCompleted) ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Doğrula',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Yeniden gönder
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Kod gelmedi mi? ',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                GestureDetector(
                  onTap: _countdown > 0 ? null : _resendCode,
                  child: Text(
                    _countdown > 0
                        ? 'Yeniden gönder (${_countdown}s)'
                        : 'Yeniden gönder',
                    style: TextStyle(
                      color: _countdown > 0
                          ? Colors.grey.shade400
                          : const Color(0xFF1877F2),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration: _countdown > 0
                          ? TextDecoration.none
                          : TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            
            if (_isResending) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1877F2)),
              ),
            ],
            
            const Spacer(),
            
            // Basit bilgi
            Text(
              'Kod 5 dakika geçerlidir',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
