import 'package:flutter/material.dart';
import '../../../Models/order.dart';
import '../../../Models/product.dart';
import '../../../Services/api_service.dart';
import '../../../Widgets/custom_dialog.dart';
import '../../../Utils/language_manager.dart';
import '../../../Utils/app_config.dart';
import '../../../Models/session.dart';

class ProductReviewPage extends StatefulWidget {
  final Order order;
  final List<Product> products;

  const ProductReviewPage({
    Key? key,
    required this.order,
    required this.products,
  }) : super(key: key);

  @override
  State<ProductReviewPage> createState() => _ProductReviewPageState();
}

class _ProductReviewPageState extends State<ProductReviewPage> {
  final Map<int, double> _ratings = {};
  final Map<int, TextEditingController> _commentControllers = {};
  bool _isSubmitting = false;
  bool _allReviewed = false; // <-- yeni eklenen state

  @override
  void initState() {
    super.initState();
    // Initialize ratings and comment controllers for each product
    for (var product in widget.products) {
      _ratings[int.parse(product.id)] = 0.0;
      _commentControllers[int.parse(product.id)] = TextEditingController();
    }
    _checkAllProductsReviewed(); // <-- yeni kontrol
  }

  Future<void> _checkAllProductsReviewed() async {
    final userId = Session.currentUser?.id;
    if (userId == null) return;
    
    try {
      final reviewedProductIds = await ApiService.fetchUserReviewedProductIds(userId);
      final productIds = widget.products.map((p) => int.tryParse(p.id) ?? -1).toList();
      final allReviewed = productIds.every((id) => reviewedProductIds.contains(id));
      
      setState(() {
        _allReviewed = allReviewed;
      });
    } catch (e) {
      print('Error checking reviewed products: ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    // Dispose all text controllers
    for (var controller in _commentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submitReviews() async {
    if (_ratings.values.any((rating) => rating == 0.0)) {
      CustomDialog.showWarning(
        context: context,
        title: LanguageManager.translate('Uyarı'),
        message: LanguageManager.translate('Lütfen tüm ürünleri değerlendirin'),
        buttonText: LanguageManager.translate('Tamam'),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Submit reviews for each product
      for (var product in widget.products) {
        final productId = int.parse(product.id);
        final rating = _ratings[productId]!;
        final comment = _commentControllers[productId]!.text.trim();
        
        await ApiService.submitProductReview(
          productId: product.id,
          sellerId: product.sellerId ?? 0,
          rating: rating.toInt(),
          comment: comment,
        );
      }

      // Değerlendirme başarılı olduktan sonra state'i güncelle
      setState(() {
        _allReviewed = true;
      });

      CustomDialog.showSuccess(
        context: context,
        title: LanguageManager.translate('Başarılı'),
        message: LanguageManager.translate('Değerlendirmeleriniz başarıyla gönderildi'),
        buttonText: LanguageManager.translate('Tamam'),
        onButtonPressed: () {
          Navigator.pop(context, true); // Başarılı olduğunu belirt
        },
      );
    } catch (e) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Değerlendirme gönderilirken hata oluştu'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Widget _buildProductReviewCard(Product product) {
    final productId = int.parse(product.id);
    final rating = _ratings[productId] ?? 0.0;
    final commentController = _commentControllers[productId]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product info
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    product.imageUrl.isNotEmpty ? AppConfig.getImageUrl(product.imageUrl) : '',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 60,
                        height: 60,
                        color: Colors.grey[200],
                        child: Icon(
                          Icons.image_not_supported,
                          color: Colors.grey[400],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
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
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₺${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Rating section
            Text(
              LanguageManager.translate('Ürün Değerlendirmesi'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _ratings[int.parse(product.id)] = (index + 1).toDouble();
                    });
                  },
                  child: Icon(
                    index < rating ? Icons.star : Icons.star_border,
                    color: index < rating ? Colors.amber : Colors.grey,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              '${rating.toInt()} / 5',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Comment section
            Text(
              LanguageManager.translate('Yorumunuz (İsteğe bağlı)'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: LanguageManager.translate('Ürün hakkında düşüncelerinizi paylaşın...'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          LanguageManager.translate('Ürün Değerlendirmesi'),
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: const Color(0xFF1877F2),
        elevation: 6,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Products to review
                  Text(
                    LanguageManager.translate('Değerlendirilecek Ürünler'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Product review cards
                  ...widget.products.map((product) => _buildProductReviewCard(product)),
                ],
              ),
            ),
          ),
          
          // Submit button
          Container(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: _allReviewed
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFF1877F2), width: 2),
                        foregroundColor: const Color(0xFF1877F2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        LanguageManager.translate('Değerlendirildi'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReviews,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1877F2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                              LanguageManager.translate('Değerlendirmeleri Gönder'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
