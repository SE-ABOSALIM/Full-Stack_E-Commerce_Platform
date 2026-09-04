import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../../Models/seller.dart';
import '../../Services/seller_api_service.dart';
import '../../Services/api_service.dart';
import '../../Widgets/custom_dialog.dart';
import '../../Utils/language_manager.dart';
import '../../Utils/app_config.dart';
import '../../Utils/phone_number.dart';
import '../user/verification/phone_verification_page.dart';
import '../../Models/seller_session.dart';

class SellerEditProfilePage extends StatefulWidget {
  final Seller seller;

  const SellerEditProfilePage({Key? key, required this.seller}) : super(key: key);

  @override
  State<SellerEditProfilePage> createState() => _SellerEditProfilePageState();
}

class _SellerEditProfilePageState extends State<SellerEditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _storeDescriptionController = TextEditingController();
  
  bool _isLoading = false;
  bool _showEmailVerificationInput = false;
  bool _isSendingEmailCode = false; // Email kodu gönderme loading state
  bool _isVerifyingEmailCode = false; // Email kodu doğrulama loading state
  bool _canSendEmailCode = true; // Email kodu gönderme yetkisi
  int _emailCodeCooldown = 0; // Email kodu bekleme süresi (saniye)
  late TextEditingController _emailVerificationController;
  File? _selectedLogo;
  final ImagePicker _picker = ImagePicker();
  
  // Güncel satıcı bilgilerini tutmak için
  late Seller _currentSeller;
  
  // Kargo şirketleri listesi
  final List<String> _cargoCompanies = [
    'Araskargo',
    'Yurticikargo',
    'MNG Kargo',
    'Pttkargo',
    'Jetkargo',
    'Süratkargo',
    'UPS Kargo',
    'DHL Express',
  ];
  String _selectedCargoCompany = 'Araskargo';

  @override
  void initState() {
    super.initState();
    _emailVerificationController = TextEditingController();
    _currentSeller = widget.seller;
    print('DEBUG: Seller profile initialized');
    _initializeControllers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sayfa yeniden açıldığında seller verisini yenile
    _refreshSellerData();
  }

  // Seller verisini yenile
  Future<void> _refreshSellerData() async {
    try {
      final updatedSeller = await SellerApiService.getSellerById(_currentSeller.id);
      if (mounted) {
        print('DEBUG: Seller profile refreshed');
        setState(() {
          _currentSeller = updatedSeller;
          // Controller'ları da güncel verilerle güncelle
          _nameController.text = updatedSeller.name;
          _emailController.text = updatedSeller.email;
          _phoneController.text = updatedSeller.phone;
          _storeNameController.text = updatedSeller.storeName;
          _storeDescriptionController.text = updatedSeller.storeDescription ?? '';
          _selectedCargoCompany = updatedSeller.cargoCompany ?? 'Araskargo';
        });
      }
    } catch (e) {
      // Hata durumunda sessizce devam et
      debugPrint('Seller data refresh error: ${e.runtimeType}');
    }
  }

  void _initializeControllers() {
    _nameController.text = _currentSeller.name;
    _emailController.text = _currentSeller.email;
    _phoneController.text = _currentSeller.phone;
    _storeNameController.text = _currentSeller.storeName;
    _storeDescriptionController.text = _currentSeller.storeDescription ?? '';
    _selectedCargoCompany = _currentSeller.cargoCompany ?? 'Araskargo';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _storeNameController.dispose();
    _storeDescriptionController.dispose();
    _emailVerificationController.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      
      if (image != null) {
        setState(() {
          _selectedLogo = File(image.path);
        });
      }
    } catch (e) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Logo seçilirken hata oluştu. Lütfen tekrar deneyin.'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    }
  }

  void _removeLogo() {
    setState(() {
      _selectedLogo = null;
    });
  }

  // Email doğrulama kodu gönder
  Future<void> _sendEmailVerificationCode() async {
    print('DEBUG: _sendEmailVerificationCode metodu çağrıldı');
    if (!_canSendEmailCode) return;

    setState(() {
      _isSendingEmailCode = true;
    });

    try {
      print('DEBUG: Email verification API çağrısı yapılıyor...');
      await ApiService.sendSellerEmailVerificationCode(_currentSeller.email);
      
      setState(() {
        _showEmailVerificationInput = true;
        _isSendingEmailCode = false;
        _canSendEmailCode = false;
        _emailCodeCooldown = 30;
      });
      
      // 30 saniyelik bekleme süresi başlat
      _startEmailCodeCooldown();
      
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: LanguageManager.translate('Email doğrulama kodu gönderildi! 30 saniye sonra tekrar kod gönderebilirsiniz.'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } catch (e) {
      setState(() {
        _isSendingEmailCode = false;
      });
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: e.toString().replaceAll('Exception: ', ''),
        buttonText: LanguageManager.translate('Tamam'),
      );
    }
  }

  // Email kodu bekleme süresini başlat
  void _startEmailCodeCooldown() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        if (_emailCodeCooldown > 0) {
          _emailCodeCooldown--;
        } else {
          _canSendEmailCode = true;
          timer.cancel();
        }
      });
    });
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
      _isVerifyingEmailCode = true;
    });

    try {
      await ApiService.verifySellerEmail(_currentSeller.email, _emailVerificationController.text);
      
      // Email doğrulandıktan sonra seller verisini yenile
      final updatedSeller = await SellerApiService.getSellerById(_currentSeller.id);
      
      setState(() {
        _showEmailVerificationInput = false;
        _emailVerificationController.clear();
        _isVerifyingEmailCode = false;
        // _currentSeller'ı güncel verilerle güncelle
        _currentSeller = updatedSeller;
      });
      
      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: LanguageManager.translate('Email adresi başarıyla doğrulandı!'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } catch (e) {
      setState(() {
        _isVerifyingEmailCode = false;
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
  Future<void> _navigateToPhoneVerification() async {
    print('DEBUG: _navigateToPhoneVerification metodu çağrıldı');
    // Profilden doğrulama başlatılırken backend'e kod göndert
    print('DEBUG: Telefon verification API çağrısı yapılıyor...');
    ApiService.sendSellerPhoneVerificationBySellerId(_currentSeller.id).catchError((e) {
      // Arka plan hatasını sessizce logla, sayfaya geçişe engel olma
      debugPrint('sendSellerPhoneVerificationBySellerId error: ${e.runtimeType}');
    });

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PhoneVerificationPage(
          phoneNumber: _currentSeller.phone,
          userType: 'seller',
          userData: {
            'name': _currentSeller.name,
            'email': _currentSeller.email,
            'password': '', // Şifre gerekli değil
            'phone': _currentSeller.phone,
          },
        ),
      ),
    );
    
    // Telefon doğrulama sayfasından döndükten sonra seller verisini yenile
    if (result == true) {
      final updatedSeller = await SellerApiService.getSellerById(_currentSeller.id);
      setState(() {
        _currentSeller = updatedSeller;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // Email veya telefon değişikliği kontrolü
    bool emailChanged = _emailController.text != _currentSeller.email;
    bool phoneChanged = !samePhoneIdentity(
      _phoneController.text,
      _currentSeller.phone,
    );
    
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
      final updatedSeller = await SellerApiService.updateProfile(
        sellerId: _currentSeller.id,
        name: _nameController.text,
        email: _emailController.text,
        phone: _phoneController.text,
        storeName: _storeNameController.text,
        storeDescription: _storeDescriptionController.text.isNotEmpty 
            ? _storeDescriptionController.text 
            : null,
        cargoCompany: _selectedCargoCompany,
        logoFile: _selectedLogo,
      );

      // CRITICAL: API'den dönen seller verisi eksik olabilir (followers_count gibi)
      // Mevcut seller verisini koruyarak eksik alanları doldur
      final completeUpdatedSeller = _currentSeller.copyWith(
        name: updatedSeller.name,
        email: updatedSeller.email,
        phone: updatedSeller.phone,
        storeName: updatedSeller.storeName,
        storeDescription: updatedSeller.storeDescription,
        storeLogo: updatedSeller.storeLogo,
        cargoCompany: updatedSeller.cargoCompany,
        phoneVerified: updatedSeller.phoneVerified,
        emailVerified: updatedSeller.emailVerified,
        isVerified: updatedSeller.isVerified,
        updatedAt: updatedSeller.updatedAt,
        // followers_count ve diğer alanları mevcut seller'dan koru
        followersCount: _currentSeller.followersCount,
        createdAt: _currentSeller.createdAt,
      );

      // Başarı mesajı
      String successMessage = LanguageManager.translate('Profil başarıyla güncellendi');
      if (emailChanged || phoneChanged) {
        successMessage += '\n\n';
        if (emailChanged) {
          successMessage += LanguageManager.translate('Email doğrulama durumu sıfırlandı. Lütfen yeni email adresinizi doğrulayın.');
        }
        if (phoneChanged) {
          successMessage += LanguageManager.translate('Telefon doğrulama kodu yeni numaranıza gönderildi. Lütfen telefon numaranızı doğrulayın.');
        }
      }

      // Profil güncelleme sonrası seller verisini güncelle
      setState(() {
        // _currentSeller'ı güncel verilerle güncelle
        _currentSeller = completeUpdatedSeller;
        // Controller'ları da güncel verilerle güncelle
        _nameController.text = completeUpdatedSeller.name;
        _emailController.text = completeUpdatedSeller.email;
        _phoneController.text = completeUpdatedSeller.phone;
        _storeNameController.text = completeUpdatedSeller.storeName;
        _storeDescriptionController.text = completeUpdatedSeller.storeDescription ?? '';
        _selectedCargoCompany = completeUpdatedSeller.cargoCompany ?? 'Araskargo';
      });

      // CRITICAL: SellerSession'ı güncel verilerle güncelle
      // Bu olmadan uygulamadan çıkıp girince eski bilgiler geri döner
      await SellerSession.saveSellerSession(completeUpdatedSeller);
      SellerSession.currentSeller = completeUpdatedSeller;

      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı!'),
        message: successMessage,
        buttonText: LanguageManager.translate('Tamam'),
        onButtonPressed: () {
          Navigator.pop(context, completeUpdatedSeller);
        },
      );
    } catch (e) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Profil güncellenirken hata oluştu. Lütfen tekrar deneyin.'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1877F2)),
              ),
            )
          : CustomScrollView(
              slivers: [
                // Modern App Bar
                SliverAppBar(
                  expandedHeight: 120,
                  floating: false,
                  pinned: true,
                  backgroundColor: const Color(0xFF1877F2),
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      LanguageManager.translate('Profil Düzenle'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1877F2),
                            Color(0xFF1565C0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  leading: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                
                // Content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Logo Section
                          _buildLogoSection(),
                          const SizedBox(height: 40),
                          
                          // Form Fields
                          _buildFormFields(),
                          const SizedBox(height: 40),
                          
                          // Update Button
                          _buildUpdateButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade50,
            Colors.blue.shade100,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.blue.shade200,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo Container
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipOval(
              child: _buildLogoWidget(),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Logo Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.photo_camera, size: 20),
                  label: Text(
                    LanguageManager.translate('Logo Seç'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1877F2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
              
              if (_selectedLogo != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _removeLogo,
                    icon: const Icon(Icons.delete, size: 20),
                    label: Text(
                      LanguageManager.translate('Kaldır'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoWidget() {
    if (_selectedLogo != null) {
      return Image.file(
        _selectedLogo!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultLogo();
        },
      );
    }
    
    if (_currentSeller.storeLogo != null && _currentSeller.storeLogo!.isNotEmpty) {
      return Image.network(
        AppConfig.getImageUrl(_currentSeller.storeLogo!),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.blue.shade100,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                    : null,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildDefaultLogo();
        },
      );
    }
    
    return _buildDefaultLogo();
  }

  Widget _buildDefaultLogo() {
    return Container(
      color: Colors.blue.shade100,
      child: Icon(
        Icons.store,
        size: 60,
        color: Colors.blue.shade400,
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        _buildFormField(
          controller: _nameController,
          label: LanguageManager.translate('Ad Soyad'),
          icon: Icons.person,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return LanguageManager.translate('Ad soyad gerekli');
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        _buildFormField(
          controller: _emailController,
          label: LanguageManager.translate('E-posta'),
          icon: Icons.email,
          keyboardType: TextInputType.emailAddress,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return LanguageManager.translate('E-posta gerekli');
            }
            if (!value.contains('@')) {
              return LanguageManager.translate('Geçerli bir e-posta adresi giriniz');
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        // Email Doğrulama Satırı
        _buildEmailVerificationRow(),
        
        const SizedBox(height: 20),
        
        _buildFormField(
          controller: _phoneController,
          label: LanguageManager.translate('Telefon'),
          icon: Icons.phone,
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return LanguageManager.translate('Telefon numarası gerekli');
            }
            if (!isValidPhoneNumber(value)) {
              return LanguageManager.translate('Geçerli bir telefon numarası giriniz');
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        // Telefon Doğrulama Satırı
        _buildPhoneVerificationRow(),
        
        const SizedBox(height: 20),
        
        _buildFormField(
          controller: _storeNameController,
          label: LanguageManager.translate('Mağaza Adı'),
          icon: Icons.store,
          validator: (value) {
            if (value == null || value.isEmpty) {
              return LanguageManager.translate('Mağaza adı gerekli');
            }
            return null;
          },
        ),
        
        const SizedBox(height: 20),
        
        _buildFormField(
          controller: _storeDescriptionController,
          label: LanguageManager.translate('Mağaza Açıklaması'),
          icon: Icons.description,
          maxLines: 4,
        ),
        
        const SizedBox(height: 20),
        
        _buildCargoCompanyField(),
      ],
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1877F2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1877F2),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1877F2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: label,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF1877F2), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.red.shade300, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black87,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildEmailVerificationRow() {
    final isEmailVerified = _currentSeller.emailVerified == 'verified';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEmailVerified ? Icons.verified : Icons.email_outlined,
                color: isEmailVerified ? Colors.green : Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                LanguageManager.translate('Email Doğrulama'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1877F2),
                ),
              ),
              const SizedBox(width: 8),
              if (isEmailVerified)
                Icon(Icons.check_circle, color: Colors.green, size: 20)
              else
                Icon(Icons.warning, color: Colors.orange, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isEmailVerified 
              ? LanguageManager.translate('Email doğrulanmış')
              : LanguageManager.translate('Email doğrulanmamış'),
            style: TextStyle(
              color: isEmailVerified ? Colors.green : Colors.orange,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!isEmailVerified) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (!_canSendEmailCode || _isSendingEmailCode) ? null : () {
                print('DEBUG: Email verification butonuna tıklandı');
                _sendEmailVerificationCode();
              },
              icon: _isSendingEmailCode 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 16),
              label: Text(
                _isSendingEmailCode 
                  ? LanguageManager.translate('Gönderiliyor...')
                  : !_canSendEmailCode 
                    ? '${LanguageManager.translate('Tekrar Gönder')} (${_emailCodeCooldown}s)'
                    : LanguageManager.translate('Doğrulama Kodu Gönder'),
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          if (_showEmailVerificationInput) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailVerificationController,
                    decoration: InputDecoration(
                      hintText: LanguageManager.translate('Doğrulama kodu'),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF1877F2), width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isVerifyingEmailCode ? null : _verifyEmailCode,
                  child: _isVerifyingEmailCode 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(LanguageManager.translate('Doğrula')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneVerificationRow() {
    final isPhoneVerified = _currentSeller.phoneVerified == 'verified';
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPhoneVerified ? Icons.verified : Icons.phone_outlined,
                color: isPhoneVerified ? Colors.green : Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                LanguageManager.translate('Telefon Doğrulama'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1877F2),
                ),
              ),
              const SizedBox(width: 8),
              if (isPhoneVerified)
                Icon(Icons.check_circle, color: Colors.green, size: 20)
              else
                Icon(Icons.warning, color: Colors.orange, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPhoneVerified 
              ? LanguageManager.translate('Telefon doğrulanmış')
              : LanguageManager.translate('Telefon doğrulanmamış'),
            style: TextStyle(
              color: isPhoneVerified ? Colors.green : Colors.orange,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!isPhoneVerified) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                print('DEBUG: Telefon verification butonuna tıklandı');
                _navigateToPhoneVerification();
              },
              icon: const Icon(Icons.phone, size: 16),
              label: Text(
                LanguageManager.translate('Telefonu Doğrula'),
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1877F2),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCargoCompanyField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1877F2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.local_shipping,
                color: Color(0xFF1877F2),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              LanguageManager.translate('Kargo Şirketi'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1877F2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: DropdownButtonFormField<String>(
            value: _selectedCargoCompany,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
            items: _cargoCompanies.map((String company) {
              return DropdownMenuItem<String>(
                value: company,
                child: Text(
                  company,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedCargoCompany = newValue!;
              });
            },
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return LanguageManager.translate('Kargo şirketi seçiniz');
              }
              return null;
            },
            icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1877F2)),
            dropdownColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1877F2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _updateProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1877F2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.save, size: 24),
            const SizedBox(width: 12),
            Text(
              LanguageManager.translate('Profili Güncelle'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
