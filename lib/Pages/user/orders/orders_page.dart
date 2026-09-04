import 'package:flutter/material.dart';
import '../product/product_review_page.dart';
import '../../../Models/session.dart';
import '../../../Models/order.dart';
import '../../../Models/product.dart';
import '../../../Models/address.dart';
import '../../../Services/api_service.dart';
import '../../../Utils/language_manager.dart';
import '../../../Utils/app_config.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> with SingleTickerProviderStateMixin {
  List<Order> _orders = [];
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    final orders = await ApiService.fetchOrders();
    print('Orders received: ${orders.length}');
    
    // Debug: Delivered siparişleri kontrol et
    for (var order in orders) {
      if (order['order_status'] == 'delivered') {
        print('🔍 DELIVERED ORDER FOUND:');
        print('  ID: ${order['id']}');
        print('  Code: ${order['order_code']}');
        print('  Status: ${order['order_status']}');
        print('  Delivered Date: ${order['order_delivered_date']}');
        print('  Delivered Date Type: ${order['order_delivered_date']?.runtimeType}');
      }
    }
    
    setState(() {
      _orders = orders.map((e) {
        print('Processing order');
        return Order.fromMap(e);
      }).toList();
    });
  }

  Future<List<Product>> _getProducts(int? orderId) async {
    if (Session.currentUser == null) return [];
    final productIds = await ApiService.fetchUserOrderProductIds(orderId, Session.currentUser!.id);
    final allProducts = await ApiService.fetchProducts();
    return allProducts
      .map((e) => Product.fromMap(e))
      .where((p) => productIds.contains(int.tryParse(p.id) ?? -1))
      .toList();
  }

  // Aktif siparişleri getir (teslim edilmemiş ve iptal edilmemiş)
  List<Order> get _activeOrders {
    final active = _orders.where((order) => order.orderStatus != 'delivered' && order.orderStatus != 'cancelled').toList();
    active.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    return active;
  }

  // Geçmiş siparişleri getir (teslim edilmiş)
  List<Order> get _completedOrders {
    final completed = _orders.where((order) => order.orderStatus == 'delivered').toList();
    completed.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    return completed;
  }

  // İptal edilen siparişler
  List<Order> get _cancelledOrders {
    final cancelled = _orders.where((order) => order.orderStatus == 'cancelled').toList();
    cancelled.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
    return cancelled;
  }

  Future<Address?> _getAddress(int addressId) async {
    final addresses = await ApiService.fetchAddresses();
    return addresses.map((e) => Address.fromMap(e)).firstWhere(
      (a) => a.id == addressId,
      orElse: () => Address(
        id: -1,
        city: '',
        district: '',
        neighbourhood: '',
        streetName: '',
        buildingNumber: '',
        apartmentNumber: '',
        addressName: '',
      ),
    );
  }

  Widget _buildTimeline(Order order) {
    final statusSteps = [
      {'status': 'pending', 'title': LanguageManager.translate('Sipariş Verildi'), 'description': LanguageManager.translate('Siparişiniz alındı'), 'icon': Icons.shopping_cart},
      {'status': 'processing', 'title': LanguageManager.translate('Sipariş Alındı'), 'description': LanguageManager.translate('Satıcı siparişinizi işleme aldı'), 'icon': Icons.check_circle},
      {'status': 'shipped', 'title': LanguageManager.translate('Kargoya Verildi'), 'description': LanguageManager.translate('Siparişiniz kargoya verildi'), 'icon': Icons.local_shipping},
      {'status': 'delivered', 'title': LanguageManager.translate('Teslim Edildi'), 'description': LanguageManager.translate('Siparişiniz teslim edildi'), 'icon': Icons.done_all},
    ];

    final currentStatusIndex = statusSteps.indexWhere((step) => step['status'] == order.orderStatus);
    final currentIndex = currentStatusIndex >= 0 ? currentStatusIndex : 0;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LanguageManager.translate('Sipariş Durumu'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...statusSteps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isCompleted = index <= currentIndex;
            final isCurrent = index == currentIndex;

            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                                     Container(
                     width: 40,
                     height: 40,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       color: isCompleted ? Colors.green : Colors.grey[300],
                       border: (isCurrent && order.orderStatus != 'delivered') ? Border.all(color: Colors.blue, width: 3) : null,
                       boxShadow: isCompleted ? [
                         BoxShadow(
                           color: Colors.green.withOpacity(0.3),
                           blurRadius: 8,
                           offset: const Offset(0, 2),
                         )
                       ] : null,
                     ),
                    child: Icon(
                      step['icon'] as IconData,
                      color: isCompleted ? Colors.white : Colors.grey[600],
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step['title'] as String,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? Colors.black : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          step['description'] as String,
                          style: TextStyle(
                            fontSize: 13,
                            color: isCompleted ? Colors.grey[700] : Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                                     if (isCurrent && order.orderStatus != 'delivered')
                     Container(
                       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                       decoration: BoxDecoration(
                         color: Colors.blue,
                         borderRadius: BorderRadius.circular(12),
                       ),
                       child: Text(
                         LanguageManager.translate('Aktif'),
                         style: const TextStyle(
                           color: Colors.white,
                           fontSize: 12,
                           fontWeight: FontWeight.bold,
                         ),
                       ),
                     ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Siparişlerim'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: const Color(0xFF1877F2),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: LanguageManager.translate('Aktif')),
            Tab(text: LanguageManager.translate('Tamamlanan')),
            Tab(text: LanguageManager.translate('İptal')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrdersList(_activeOrders, LanguageManager.translate('Henüz aktif sipariş yok.')),
          _buildOrdersList(_completedOrders, LanguageManager.translate('Henüz geçmiş sipariş yok.')),
          _buildOrdersList(_cancelledOrders, LanguageManager.translate('Henüz iptal edilen sipariş yok.')),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<Order> orders, String emptyMessage) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              LanguageManager.translate('Henüz siparişiniz bulunmuyor'),
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return FutureBuilder<List<Product>>(
          future: _getProducts(order.id != null ? order.id! : -1),
          builder: (context, snapshot) {
            final products = snapshot.data ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${LanguageManager.translate('Sipariş Kodu')}: ${order.orderCode}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        // Sadece aktif siparişlerde durum göster
                        if (order.orderStatus != 'delivered' && _getStatusText(order.orderStatus).isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(order.orderStatus),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusText(order.orderStatus),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${LanguageManager.translate('Sipariş Tarihi')}: ${order.orderCreatedDate}'),
                    // Sadece aktif siparişlerde durum bilgilerini göster
                    if (order.orderStatus != 'delivered') ...[
                      if (order.orderStatus == 'processing' || order.orderStatus == 'shipped') ...[
                        Text('${LanguageManager.translate('Tahmini Teslim')}: ${order.orderEstimatedDelivery}'),
                      ],
                      if (order.orderStatus == 'shipped') ...[
                        Text('${LanguageManager.translate('Kargo Şirketi')}: ${order.orderCargoCompany}'),
                      ],
                    ],
                    // Geçmiş siparişlerde sadece teslim tarihi göster
                    if (order.orderStatus == 'delivered' && order.orderDeliveredDate != null) ...[
                      Text("${LanguageManager.translate('Teslim Tarihi')}: ${order.orderDeliveredDate}", 
                           style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                    FutureBuilder<Address?>(
                      future: _getAddress(order.orderAddress),
                      builder: (context, addrSnap) {
                        final addr = addrSnap.data;
                        if (addr == null) return const SizedBox();
                        return const SizedBox(); // Adres gösterimini kaldırdık
                      },
                    ),
                    const Divider(),
                    Text('${LanguageManager.translate('Ürünler')}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...products.map((p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Image.network(
                            p.imageUrl.isNotEmpty ? AppConfig.getImageUrl(p.imageUrl) : '',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.image),
                          ),
                          title: Text(p.name),
                          subtitle: Text('₺${p.price.toStringAsFixed(2)}'),
                        )),
                    // Sadece aktif siparişlerde timeline göster
                    if (order.orderStatus != 'delivered') ...[
                      _buildTimeline(order),
                    ],
                    
                    // Review button for delivered orders
                    if (order.orderStatus == 'delivered') ...[
                      const SizedBox(height: 16),
                      FutureBuilder<bool>(
                        future: _checkIfAllProductsReviewed(products),
                        builder: (context, reviewSnapshot) {
                          final allReviewed = reviewSnapshot.data ?? false;
                          
                          return SizedBox(
                            width: double.infinity,
                            child: allReviewed
                                ? OutlinedButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check_circle, color: Color(0xFF1877F2)),
                                    label: Text(
                                      LanguageManager.translate('Değerlendirildi'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1877F2),
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      side: const BorderSide(color: Color(0xFF1877F2), width: 2),
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  )
                                : ElevatedButton.icon(
                                    onPressed: () => _navigateToReviewPage(order, products),
                                    icon: const Icon(Icons.star, color: Colors.amber),
                                    label: Text(
                                      LanguageManager.translate('Ürünü Değerlendir'),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'shipped':
        return Colors.purple;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return ''; // Remove "Beklemede" text
      case 'processing':
        return LanguageManager.translate('İşleme Alındı');
      case 'shipped':
        return LanguageManager.translate('Kargoya Verildi');
      case 'delivered':
        return LanguageManager.translate('Teslim Edildi');
      case 'cancelled':
        return LanguageManager.translate('İptal Edildi');
      default:
        return LanguageManager.translate('Bilinmiyor');
    }
  }

  void _navigateToReviewPage(Order order, List<Product> products) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductReviewPage(
          order: order,
          products: products,
        ),
      ),
    ).then((result) {
      // Refresh the orders list if review was submitted successfully
      if (result == true) {
        _loadOrders();
      }
    });
  }

  Future<bool> _checkIfAllProductsReviewed(List<Product> products) async {
    if (Session.currentUser?.id == null) return false;
    final reviewedProductIds = await ApiService.fetchUserReviewedProductIds(Session.currentUser!.id!);
    final productIds = products.map((p) => int.tryParse(p.id) ?? -1).toList();
    return productIds.every((id) => reviewedProductIds.contains(id));
  }
}