import 'package:flutter/material.dart';
import 'settings_page.dart';
import '../../Models/seller.dart';
import '../../Models/product.dart';
import '../../Models/session.dart';
import '../../Services/seller_api_service.dart';
import '../../Services/api_service.dart';
import '../user/product/product_detail_page.dart';
import '../../Utils/language_manager.dart';
import '../../Utils/app_config.dart';

class SellerProfilePage extends StatefulWidget {
  final int sellerId;
  
  const SellerProfilePage({Key? key, required this.sellerId}) : super(key: key);

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> 
    with TickerProviderStateMixin {
  Seller? _seller;
  List<Product> _products = [];
  bool _isLoading = true;
  bool _isLoadingSeller = true;
  bool _isFollowing = false;
  int _followersCount = 0;
  
  // Animation controllers
  late AnimationController _followAnimationController;
  late AnimationController _rippleAnimationController;
  late AnimationController _scaleAnimationController;
  
  // Animations
  late Animation<double> _followAnimation;
  late Animation<double> _rippleAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controllers
    _followAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _rippleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    
    // Setup animations
    _followAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _followAnimationController,
      curve: Curves.elasticOut,
    ));
    
    _rippleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _rippleAnimationController,
      curve: Curves.easeOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _scaleAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _colorAnimation = ColorTween(
      begin: const Color(0xFF1877F2),
      end: Colors.green,
    ).animate(CurvedAnimation(
      parent: _followAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _loadSellerInfo();
    _loadSellerProducts();
    _checkFollowStatus();
    _loadFollowersCount();
  }

  @override
  void dispose() {
    _followAnimationController.dispose();
    _rippleAnimationController.dispose();
    _scaleAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sayfa yeniden açıldığında seller verisini ve takip durumunu yenile
    _loadSellerInfo();
    _checkFollowStatus();
    _loadFollowersCount();
  }

  Future<void> _loadSellerInfo() async {
    try {
      final seller = await SellerApiService.getSellerById(widget.sellerId);
      setState(() {
        _seller = seller;
        _isLoadingSeller = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingSeller = false;
      });
    }
  }

  Future<void> _loadSellerProducts() async {
    try {
      final products = await ApiService.fetchSellerProducts(widget.sellerId);
      setState(() {
        _products = products.map((e) => Product.fromMap(e)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkFollowStatus() async {
    try {
      if (Session.currentUser?.id != null) {
        final response = await ApiService.checkIfFollowing(
          Session.currentUser!.id!, 
          widget.sellerId
        );
        setState(() {
          _isFollowing = response['is_following'] ?? false;
        });
      }
    } catch (e) {
      print('Takip durumu kontrol edilemedi: ${e.runtimeType}');
      // Hata durumunda varsayılan olarak false
      setState(() {
        _isFollowing = false;
      });
    }
  }

  Future<void> _loadFollowersCount() async {
    try {
      // Takipçi sayısını her zaman API'den çek (en güncel ve doğru kaynak)
      final response = await ApiService.getSellerFollowersCount(widget.sellerId);
      setState(() {
        _followersCount = response['followers_count'] ?? 0;
      });
    } catch (e) {
      print('Takipçi sayısı getirilemedi: ${e.runtimeType}');
      // Hata durumunda varsayılan olarak 0
      setState(() {
        _followersCount = 0;
      });
    }
  }

  Future<void> _toggleFollow() async {
    try {
      if (Session.currentUser?.id == null) {
        // Kullanıcı giriş yapmamış
        return;
      }

      // Start scale animation
      _scaleAnimationController.forward().then((_) {
        _scaleAnimationController.reverse();
      });
      
      if (_isFollowing) {
        // Unfollow işlemi
        await ApiService.unfollowSeller(
          Session.currentUser!.id!, 
          widget.sellerId
        );
        
        // Unfollow animation
        _followAnimationController.reverse();
        setState(() {
          _isFollowing = false;
          _followersCount = (_followersCount - 1).clamp(0, double.infinity).toInt();
        });
        
        // Seller verisini güncelle (eğer mevcut seller ise)
        if (_seller != null) {
          _seller = _seller!.copyWith(followersCount: _followersCount);
        }
      } else {
        // Follow işlemi
        await ApiService.followSeller(
          Session.currentUser!.id!, 
          widget.sellerId
        );
        
        // Follow animation
        _followAnimationController.forward();
        _rippleAnimationController.forward().then((_) {
          _rippleAnimationController.reset();
        });
        
        setState(() {
          _isFollowing = true;
          _followersCount++;
        });
        
        // Seller verisini güncelle (eğer mevcut seller ise)
        if (_seller != null) {
          _seller = _seller!.copyWith(followersCount: _followersCount);
        }
      }
    } catch (e) {
      print('Takip işlemi başarısız: ${e.runtimeType}');
      
      // State'i geri al
      setState(() {
        if (_isFollowing) {
          _isFollowing = false;
          _followersCount = (_followersCount - 1).clamp(0, double.infinity).toInt();
        } else {
          _isFollowing = true;
          _followersCount++;
        }
      });
      
      // Seller verisini de güncelle
      if (_seller != null) {
        _seller = _seller!.copyWith(followersCount: _followersCount);
      }
    }
  }

  Widget _buildFollowButton() {
    return Container(
      width: 120, // Biraz daha büyük genişlik
      height: 40, // Biraz daha büyük yükseklik
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ripple effect - daha küçük
          if (_rippleAnimation.value > 0)
            Positioned(
              child: Container(
                width: 90 * _rippleAnimation.value,
                height: 90 * _rippleAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.green.withOpacity(0.2 * (1 - _rippleAnimation.value)),
                ),
              ),
            ),
          
          // Main button - hiç boyut değişikliği yok
          GestureDetector(
            onTap: _isFollowing ? () => _showUnfollowDialog() : _toggleFollow,
            child: Container(
              width: 120,
              height: 40,
              decoration: BoxDecoration(
                gradient: _isFollowing 
                    ? LinearGradient(
                        colors: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          const Color(0xFF1877F2),
                          const Color(0xFF0056D6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: (_isFollowing ? Colors.green : const Color(0xFF1877F2))
                        .withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon with animation
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _isFollowing
                        ? Transform.rotate(
                            angle: _followAnimation.value * 2 * 3.14159,
                            child: Icon(
                              Icons.check_circle,
                              key: const ValueKey('check_icon'),
                              size: 16,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.person_add,
                            key: const ValueKey('add_icon'),
                            size: 16,
                            color: Colors.white,
                          ),
                  ),
                  const SizedBox(width: 6),
                  
                  // Text with animation
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      _isFollowing ? 'Takip Edildi' : LanguageManager.translate('Takip Et'),
                      key: ValueKey(_isFollowing ? 'following' : 'not_following'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUnfollowDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // İkon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_remove,
                    size: 32,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Başlık
                Text(
                  'Takipten Çıkar',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Mesaj
                Text(
                  '${_seller?.storeName ?? 'Bu satıcıyı'} takipten çıkarmak istediğinizden emin misiniz?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Butonlar
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Text(
                          'İptal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _toggleFollow();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade500,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Takipten Çıkar',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Satıcı Profili'), 
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          )
        ),
        backgroundColor: const Color(0xFF1877F2),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Satıcı Bilgileri
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Logo ve Mağaza Adı
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.blue.shade100,
                              child: _seller?.storeLogo != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(40),
                                      child: Image.network(
                                        AppConfig.getImageUrl(_seller!.storeLogo!),
                                        width: 80,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Icon(
                                            Icons.store,
                                            size: 40,
                                            color: Colors.blue,
                                          );
                                        },
                                      ),
                                    )
                                  : Icon(
                                      Icons.store,
                                      size: 40,
                                      color: Colors.blue,
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _seller?.storeName ?? LanguageManager.translate('Mağaza Adı'),
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // Takip Butonu
                                      _buildFollowButton(),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Takipçi Sayısı - Üstte
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people,
                                        size: 18,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$_followersCount ${LanguageManager.translate('Takipçi')}',
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_seller?.storeDescription != null && _seller!.storeDescription!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _seller!.storeDescription!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Ürünler Başlığı
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Text(
                          LanguageManager.translate('Mağaza Ürünleri'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Ürünler Listesi
                  if (_products.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            LanguageManager.translate('Bu mağazada henüz ürün bulunmuyor'),
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _products.length,
                      itemBuilder: (context, index) {
                        final product = _products[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailPage(product: product),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Ürün Resmi
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      AppConfig.getImageUrl(product.imageUrl),
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          width: 80,
                                          height: 80,
                                          color: Colors.grey[200],
                                          child: Icon(
                                            Icons.image_not_supported,
                                            color: Colors.grey[400],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Ürün Bilgileri
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          product.category,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '₺${product.price.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1877F2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Ok İkonu
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.grey[400],
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
} 