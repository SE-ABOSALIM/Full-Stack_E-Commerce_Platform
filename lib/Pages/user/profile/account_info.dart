import 'package:flutter/material.dart';
import '../../../Models/User.dart';
import '../../../Models/session.dart';
import '../../../Services/api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';
import '../verification/phone_verification_page.dart';

class AccountInfoPage extends StatefulWidget {
  const AccountInfoPage({super.key});

  @override
  State<AccountInfoPage> createState() => _AccountInfoPageState();
}

class _AccountInfoPageState extends State<AccountInfoPage> {
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  bool _isLoading = false;
  bool _showEmailVerificationInput = false;
  late TextEditingController _emailVerificationController;

  @override
  void initState() {
    super.initState();
    // Controller'ları hemen initialize et
    _nameController = TextEditingController();
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _emailVerificationController = TextEditingController();
    _loadUserInfo(); // await kullanmaya gerek yok initState'de
  }

  Future<void> _loadUserInfo() async {
    final user = Session.currentUser;
    if (user != null) {
      // Kullanıcı bilgilerini API'den yeniden al
      try {
        final users = await ApiService.fetchUsers();
        final currentUserData = users.firstWhere(
          (u) => u['email'] == user.email,
          orElse: () => user.toMap(),
        );
        
        // ID'yi koruyarak güncelle
        final updatedUser = User.fromMap(currentUserData);
        print('Account info - Updated user: $updatedUser');
        print('Account info - User ID: ${updatedUser.id}');
        
        // Session'ı güncelle
        Session.currentUser = updatedUser;
        
        // Controller'ları güncelle
        _nameController.text = updatedUser.nameSurname.isNotEmpty ? updatedUser.nameSurname : '';
        _emailController.text = updatedUser.email.isNotEmpty ? updatedUser.email : '';
        _phoneController.text = updatedUser.phoneNumber.isNotEmpty ? updatedUser.phoneNumber : '';
        
        setState(() {}); // UI'yi güncelle
      } catch (e) {
        // API'den alınamazsa mevcut bilgileri kullan
        _nameController.text = user.nameSurname.isNotEmpty ? user.nameSurname : '';
        _emailController.text = user.email.isNotEmpty ? user.email : '';
        _phoneController.text = user.phoneNumber.isNotEmpty ? user.phoneNumber : '';
        setState(() {});
      }
    } else {
      // Kullanıcı giriş yapmamış
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _emailVerificationController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (Session.currentUser == null) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Kullanıcı bilgisi bulunamadı!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    // Email veya telefon değişikliği kontrolü
    bool emailChanged = _emailController.text != Session.currentUser!.email;
    bool phoneChanged = _phoneController.text != Session.currentUser!.phoneNumber;
    
    if (emailChanged || phoneChanged) {
      // Modern uyarı dialog'u göster
      bool? shouldProceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            child: Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with icon
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 32,
                    ),
                  ),
                  SizedBox(height: 1),
                  
                  // Title
                  Text(
                    LanguageManager.translate('Uyarı'),
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  
                  // Content
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LanguageManager.translate('Aşağıdaki değişiklikler yapılacak:'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Colors.grey[800],
                          ),
                        ),
                        SizedBox(height: 12),
                        if (emailChanged) ...[
                          _buildChangeItem(
                            Icons.refresh_outlined,
                            LanguageManager.translate("Email doğrulama durumu sıfırlanacak"),
                          ),
                          _buildChangeItem(
                            Icons.verified_outlined,
                            LanguageManager.translate("Yeni email için doğrulama gerekecektir"),
                          ),
                          SizedBox(height: 8),
                        ],
                        if (phoneChanged) ...[
                          _buildChangeItem(
                            Icons.phone_outlined,
                            LanguageManager.translate("Telefon numarası değiştirilecek"),
                          ),
                          _buildChangeItem(
                            Icons.refresh_outlined,
                            LanguageManager.translate("Telefon doğrulama durumu sıfırlanacak"),
                          ),
                          _buildChangeItem(
                            Icons.verified_outlined,
                            LanguageManager.translate("Yeni telefon için doğrulama gerekli"),
                          ),
                          SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  
                  // Question
                  Text(
                    LanguageManager.translate('Devam etmek istiyor musunuz?'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              LanguageManager.translate('İptal'),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              LanguageManager.translate('Devam Et'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      
      if (shouldProceed != true) {
        return; // Kullanıcı iptal etti
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final updatedUser = User(
        id: Session.currentUser!.id,
        nameSurname: _nameController.text,
        password: '',
        email: _emailController.text,
        phoneNumber: _phoneController.text,
      );
      
      await ApiService.updateUser(updatedUser.id!, {
        'name_surname': updatedUser.nameSurname,
        'email': updatedUser.email,
        'phone_number': updatedUser.phoneNumber,
      });
      
      Session.currentUser = updatedUser;
      
      setState(() {
        _isLoading = false;
      });
      
      // Başarı mesajı
      String successMessage = LanguageManager.translate('Bilgiler başarıyla güncellendi!');
      if (emailChanged || phoneChanged) {
        successMessage += '\n\n';
        if (emailChanged) {
          successMessage += LanguageManager.translate('Email doğrulama durumu sıfırlandı. Lütfen yeni email adresinizi doğrulayın.');
        }
        if (phoneChanged) {
          successMessage += LanguageManager.translate('Telefon doğrulama kodu yeni numaranıza gönderildi. Lütfen telefon numaranızı doğrulayın.');
        }
      }
      
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: successMessage,
        buttonText: LanguageManager.translate('Tamam'),
        onButtonPressed: () {
          Navigator.pop(context);
          // Bilgileri yeniden yükle
          _loadUserInfo();
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Bilgiler güncellenirken hata oluştu. Lütfen tekrar deneyin.'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    }
  }

  // Email doğrulama kodu gönder
  Future<void> _sendEmailVerificationCode() async {
    if (Session.currentUser == null) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Kullanıcı bilgisi bulunamadı!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.sendEmailVerificationCode(Session.currentUser!.email);
      
      setState(() {
        _showEmailVerificationInput = true;
        _isLoading = false;
      });
      
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: LanguageManager.translate('Email doğrulama kodu gönderildi!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: e.toString().replaceAll('Exception: ', ''),
        buttonText: LanguageManager.translate('Tamam'),
      );
    }
  }

  // Email doğrulama kodunu doğrula
  Future<void> _verifyEmailCode() async {
    if (_emailVerificationController.text.isEmpty) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Lütfen doğrulama kodunu girin!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ApiService.verifyEmail(Session.currentUser!.email, _emailVerificationController.text);
      
      // Kullanıcı bilgilerini yeniden yükle
      await _loadUserInfo();
      
      setState(() {
        _showEmailVerificationInput = false;
        _emailVerificationController.clear();
        _isLoading = false;
      });
      
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: LanguageManager.translate('Email adresi başarıyla doğrulandı!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: e.toString().replaceAll('Exception: ', ''),
        buttonText: LanguageManager.translate('Tamam'),
      );
    }
  }

  // Telefon doğrulama sayfasına yönlendir
  void _navigateToPhoneVerification() {
    // Profilden doğrulama başlatılırken backend'e kod göndert
    if (Session.currentUser?.id != null) {
      ApiService.sendUserPhoneVerificationByUserId(Session.currentUser!.id!).catchError((e) {
        // Arka plan hatasını sessizce logla, sayfaya geçişe engel olma
        debugPrint('sendUserPhoneVerificationByUserId error: $e');
      });
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhoneVerificationPage(
          phoneNumber: Session.currentUser!.phoneNumber,
          userType: 'user',
          userData: const {},
          isRegistration: false,
        ),
      ),
    ).then((_) {
      // Sayfa döndüğünde kullanıcı bilgilerini yeniden yükle
      _loadUserInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (Session.currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            LanguageManager.translate('Hesap Bilgilerim'),
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: Color(0xFF1877F2),
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
        ),
        body: Center(
          child: Text(
            LanguageManager.translate('Bu sayfayı kullanabilmek için giriş yapmanız gerekmektedir.'),
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Hesap Bilgilerim'),
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Color(0xFF1877F2),
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Profil Kartı
              Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        LanguageManager.translate('Kişisel Bilgilerim'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1877F2),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.blue.shade100,
                        child: Icon(Icons.person, size: 50, color: Colors.blue.shade700),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        Session.currentUser?.nameSurname ?? LanguageManager.translate('Kullanıcı'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Session.currentUser?.email ?? '',
                        style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                        textAlign: TextAlign.center,
                      ),
                      const Divider(height: 32, thickness: 1.2),
                      _buildProfileInfoRow(Icons.person, LanguageManager.translate('Ad Soyad'), _nameController),
                      _buildProfileInfoRow(Icons.email, LanguageManager.translate('E-posta'), _emailController),
                      _buildEmailVerificationRow(),
                      _buildProfileInfoRow(Icons.phone, LanguageManager.translate('Telefon'), _phoneController),
                      _buildPhoneVerificationRow(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Kaydet Butonu
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _saveChanges,
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save, size: 24),
                  label: Text(
                    _isLoading ? LanguageManager.translate('Kaydediliyor...') : LanguageManager.translate('Değişiklikleri Kaydet'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1877F2),
                    foregroundColor: Colors.white,
                    elevation: 8,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    shadowColor: Colors.black45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoRow(IconData icon, String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blueGrey, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: label,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1877F2), width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailVerificationRow() {
    final user = Session.currentUser;
    final isEmailVerified = user?.emailVerified == 'verified';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isEmailVerified ? Icons.verified : Icons.email_outlined,
            color: isEmailVerified ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      LanguageManager.translate('Email Doğrulama'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isEmailVerified)
                      Icon(Icons.check_circle, color: Colors.green, size: 16)
                    else
                      Icon(Icons.warning, color: Colors.orange, size: 16),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isEmailVerified 
                    ? LanguageManager.translate('Email doğrulanmış')
                    : LanguageManager.translate('Email doğrulanmamış'),
                  style: TextStyle(
                    color: isEmailVerified ? Colors.green : Colors.orange,
                    fontSize: 12,
                  ),
                ),
                if (!isEmailVerified) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendEmailVerificationCode,
                    icon: _isLoading 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send, size: 16),
                    label: Text(
                      _isLoading 
                        ? LanguageManager.translate('Gönderiliyor...')
                        : LanguageManager.translate('Doğrulama Kodu Gönder'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1877F2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
                if (_showEmailVerificationInput) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emailVerificationController,
                          decoration: InputDecoration(
                            hintText: LanguageManager.translate('Doğrulama kodu'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _verifyEmailCode,
                        child: _isLoading 
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(LanguageManager.translate('Doğrula')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneVerificationRow() {
    final user = Session.currentUser;
    final isPhoneVerified = user?.phoneVerified == 'verified';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPhoneVerified ? Icons.verified : Icons.phone_outlined,
            color: isPhoneVerified ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      LanguageManager.translate('Telefon Doğrulama'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isPhoneVerified)
                      Icon(Icons.check_circle, color: Colors.green, size: 16)
                    else
                      Icon(Icons.warning, color: Colors.orange, size: 16),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isPhoneVerified 
                    ? LanguageManager.translate('Telefon doğrulanmış')
                    : LanguageManager.translate('Telefon doğrulanmamış'),
                  style: TextStyle(
                    color: isPhoneVerified ? Colors.green : Colors.orange,
                    fontSize: 12,
                  ),
                ),
                if (!isPhoneVerified) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _navigateToPhoneVerification,
                    icon: const Icon(Icons.phone, size: 16),
                    label: Text(
                      LanguageManager.translate('Telefonu Doğrula'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1877F2),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: Colors.orange,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
