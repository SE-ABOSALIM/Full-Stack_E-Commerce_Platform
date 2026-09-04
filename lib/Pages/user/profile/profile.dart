import 'package:flutter/material.dart';
import '../../../Services/auth_session.dart';
import 'account_info.dart';
import 'favorites_page.dart';
import 'my_addresses.dart';
import 'my_credit_cards.dart';
import 'settings_page.dart';
import 'followed_sellers_page.dart';
import '../auth/login.dart';
import '../cart/my_cart.dart';
import '../orders/orders_page.dart';
import '../../../Models/session.dart';
import '../../../Utils/language_manager.dart';

class ProfileContent extends StatelessWidget {
  const ProfileContent({super.key});

  Future<void> _logout(BuildContext context) async {
    await CartManager.clearCart();
    await AuthSession.clear('user');
    Session.currentUser = null;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = Session.currentUser != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 65, left: 20, right: 20),
      child: Column(
        children: [
          // Modern Header Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
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
                  color: const Color(0xFF1877F2).withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Profile Avatar
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                
                // User Info
                Text(
                  isLoggedIn 
                      ? Session.currentUser?.nameSurname ?? 'Kullanıcı'
                      : LanguageManager.translate('Hoş Geldiniz'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isLoggedIn 
                      ? Session.currentUser?.email ?? ''
                      : LanguageManager.translate('Hesap bilgileriniz'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Menu Items Section
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Column(
              children: [
                _buildModernProfileItem(
                  icon: Icons.person_outline,
                  title: LanguageManager.translate('Hesap Bilgileri'),
                  subtitle: LanguageManager.translate('Kişisel bilgilerinizi yönetin'),
                  onTap: () {
                    if (Session.currentUser == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginPage(
                            infoMessage: LanguageManager.translate('Bu alanı kullanabilmek için giriş yapmanız gerekmektedir'),
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AccountInfoPage()),
                      );
                    }
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.shopping_bag_outlined,
                  title: LanguageManager.translate('Siparişlerim'),
                  subtitle: LanguageManager.translate('Sipariş geçmişinizi görüntüleyin'),
                  onTap: () {
                    if (Session.currentUser == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginPage(
                            infoMessage: LanguageManager.translate('Bu alanı kullanabilmek için giriş yapmanız gerekmektedir'),
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const OrdersPage()),
                      );
                    }
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.favorite_outline,
                  title: LanguageManager.translate('Favorilerim'),
                  subtitle: LanguageManager.translate('Beğendiğiniz ürünleri görüntüleyin'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const FavoritesPage()),
                    );
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.store_outlined,
                  title: LanguageManager.translate('Takip Ettiğim Satıcılar'),
                  subtitle: LanguageManager.translate('Takip ettiğiniz satıcıları yönetin'),
                  onTap: () {
                    if (Session.currentUser == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginPage(
                            infoMessage: LanguageManager.translate('Bu alanı kullanabilmek için giriş yapmanız gerekmektedir'),
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const FollowedSellersPage()),
                      );
                    }
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.location_on_outlined,
                  title: LanguageManager.translate('Adreslerim'),
                  subtitle: LanguageManager.translate('Kayıtlı adreslerinizi yönetin'),
                  onTap: () {
                    if (Session.currentUser == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginPage(
                            infoMessage: LanguageManager.translate('Bu alanı kullanabilmek için giriş yapmanız gerekmektedir'),
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MyAddressesPage(userId: Session.currentUser?.id ?? 0),
                        ),
                      );
                    }
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.credit_card_outlined,
                  title: LanguageManager.translate('Ödeme Yöntemleri'),
                  subtitle: LanguageManager.translate('Kart bilgilerinizi yönetin'),
                  onTap: () {
                    if (Session.currentUser == null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LoginPage(
                            infoMessage: LanguageManager.translate('Bu alanı kullanabilmek için giriş yapmanız gerekmektedir'),
                          ),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MyCreditCardsPage(userId: Session.currentUser?.id ?? 0),
                        ),
                      );
                    }
                  },
                ),
                _buildDivider(),
                _buildModernProfileItem(
                  icon: Icons.settings_outlined,
                  title: LanguageManager.translate('Ayarlar'),
                  subtitle: LanguageManager.translate('Uygulama ayarlarınızı yönetin'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Logout Button
          if (isLoggedIn)
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                label: Text(
                  LanguageManager.translate('Çıkış Yap'),
                  style: const TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.w600, 
                    color: Colors.white
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade500,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  elevation: 0,
                  shadowColor: Colors.red.withOpacity(0.3),
                ),
                onPressed: () => _logout(context),
              ),
            ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModernProfileItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Icon Container
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1877F2).withOpacity(0.1),
                    const Color(0xFF0056D6).withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1877F2),
                size: 24,
              ),
            ),
            
            const SizedBox(width: 16),
            
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            
            // Arrow Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: Colors.grey[200],
    );
  }
}
