import 'package:flutter/material.dart';
import '../home.dart' as home;
import '../../seller/profile_page.dart';
import '../../../Models/seller.dart';
import '../../../Services/api_service.dart';
import '../../../Utils/language_manager.dart';
import '../../../Utils/app_config.dart';
import '../../../Models/session.dart';

class FollowedSellersPage extends StatefulWidget {
  const FollowedSellersPage({Key? key}) : super(key: key);

  @override
  State<FollowedSellersPage> createState() => _FollowedSellersPageState();
}

class _FollowedSellersPageState extends State<FollowedSellersPage> {
  List<Map<String, dynamic>> _followedSellers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowedSellers();
  }

  Future<void> _loadFollowedSellers() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Gerçek user ID'yi al
      final userId = Session.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen önce giriş yapın!')),
        );
        return;
      }
      
      final response = await ApiService.getFollowedSellers(userId);
      
      // Veri tipini güvenli şekilde cast et
      final dynamic followedSellersData = response['followed_sellers'];
      List<Map<String, dynamic>> followedSellers = [];
      
      if (followedSellersData is List) {
        for (var item in followedSellersData) {
          if (item is Map<String, dynamic>) {
            followedSellers.add(item);
          }
        }
      }
      
      setState(() {
        _followedSellers = followedSellers;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Takip edilen satıcılar yüklenemedi: ${e.runtimeType}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Takip Ettiğim Satıcılar'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF1877F2),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF1877F2),
                          const Color(0xFF0056D6),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Yükleniyor...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : _followedSellers.isEmpty
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Modern Empty State Icon
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.grey[300]!,
                                Colors.grey[400]!,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(60),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.store_outlined,
                            size: 60,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          LanguageManager.translate('Henüz hiç satıcı takip etmiyorsunuz'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          LanguageManager.translate('Satıcıları takip etmek için satıcı profillerini ziyaret edin'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        // Modern Button
                        Container(
                          width: 200,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF1877F2),
                                const Color(0xFF0056D6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1877F2).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                                                             onTap: () {
                                 Navigator.pushAndRemoveUntil(
                                   context,
                                   MaterialPageRoute(
                                     builder: (context) => const home.HomePage(skipSellerCheck: true),
                                   ),
                                   (route) => false,
                                 );
                               },
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.explore,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Keşfet',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _followedSellers.length,
                  itemBuilder: (context, index) {
                    final seller = _followedSellers[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SellerProfilePage(
                                  sellerId: seller['id'],
                                ),
                              ),
                            );
                            // Satıcı profilinden geri döndüğünde listeyi yenile
                            _loadFollowedSellers();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                // Modern Avatar
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue.shade100,
                                        Colors.blue.shade200,
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: seller['store_logo_url'] != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(15),
                                          child: Image.network(
                                            AppConfig.getImageUrl(seller['store_logo_url']),
                                            width: 60,
                                            height: 60,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return Icon(
                                                Icons.store,
                                                size: 30,
                                                color: Colors.blue.shade700,
                                              );
                                            },
                                          ),
                                        )
                                      : Icon(
                                          Icons.store,
                                          size: 30,
                                          color: Colors.blue.shade700,
                                        ),
                                ),
                                
                                const SizedBox(width: 16),
                                
                                // Seller Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        seller['store_name'] ?? 'Mağaza Adı',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (seller['store_description'] != null && seller['store_description'].isNotEmpty)
                                        Text(
                                          seller['store_description'],
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      
                                    ],
                                  ),
                                ),
                                
                                // Arrow Icon
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.grey[600],
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
