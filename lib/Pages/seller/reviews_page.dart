import 'package:flutter/material.dart';
import '../../Models/seller_review.dart';
import '../../Models/product.dart';
import '../../Models/seller.dart';
import '../../Services/api_service.dart';
import '../../Widgets/custom_dialog.dart';
import '../../Utils/language_manager.dart';
import '../../Utils/app_config.dart';
import '../../Utils/privacy_manager.dart';

class SellerReviewsPage extends StatefulWidget {
  final Seller seller;
  
  const SellerReviewsPage({Key? key, required this.seller}) : super(key: key);

  @override
  State<SellerReviewsPage> createState() => _SellerReviewsPageState();
}

class _SellerReviewsPageState extends State<SellerReviewsPage> {
  List<Product> _products = [];
  bool _isLoading = true;
  Map<int, List<dynamic>> _productReviews = {};
  Map<int, double> _averageRatings = {};
  String _selectedCategory = 'Tüm Kategoriler';
  List<String> _categories = ['Tüm Kategoriler'];

  @override
  void initState() {
    super.initState();
    _loadSellerProducts();
    // Dil değişikliklerini dinle
    LanguageManager.addListener(_onLanguageChanged);
  }

  @override
  void dispose() {
    LanguageManager.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    setState(() {
      // Dil değiştiğinde kategori listesini yeniden oluştur
      if (_products.isNotEmpty) {
        _updateCategories();
      }
    });
  }

  void _updateCategories() {
    final categories = _products.map((p) => p.category).toSet().toList();
    categories.sort();
    final translatedCategories = categories.map((category) => LanguageManager.translate(category)).toList();
    setState(() {
      _categories = [LanguageManager.translate('Tüm Kategoriler'), ...translatedCategories];
      // Eğer seçili kategori "Tüm Kategoriler" ise, çevrilmiş halini kullan
      if (_selectedCategory == 'Tüm Kategoriler' || _selectedCategory == LanguageManager.translate('Tüm Kategoriler')) {
        _selectedCategory = LanguageManager.translate('Tüm Kategoriler');
      } else {
        // Seçili kategoriyi çevir
        for (final product in _products) {
          if (LanguageManager.translate(product.category) == _selectedCategory) {
            _selectedCategory = LanguageManager.translate(product.category);
            break;
          }
        }
      }
    });
  }

  Future<void> _loadSellerProducts() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final products = await ApiService.fetchSellerProducts(widget.seller.id);
      final productList = products.map((e) => Product.fromMap(Map<String, dynamic>.from(e))).toList();
      
      // Kategorileri topla ve çevir
      setState(() {
        _products = productList;
        _isLoading = false;
      });
      _updateCategories();
      
      // Her ürün için yorumları yükle
      for (final product in productList) {
        await _loadProductReviews(int.parse(product.id.toString()));
      }

      setState(() {
        _products = productList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProductReviews(int productId) async {
    try {
      print('=== LOADING REVIEWS FOR PRODUCT ID: $productId ===');
      final reviews = await ApiService.getProductReviews(productId);
      print('=== REVIEWS LOADED: ${reviews.length} reviews ===');
      
      // Ortalama rating hesapla
      double averageRating = 0.0;
      if (reviews.isNotEmpty) {
        final totalRating = reviews.fold(0.0, (sum, review) {
          final rating = review['rating'];
          if (rating is int) {
            return sum + rating;
          } else if (rating is String) {
            final parsedRating = int.tryParse(rating);
            return sum + (parsedRating ?? 0);
          } else {
            return sum + 0;
          }
        });
        averageRating = totalRating / reviews.length;
      }

      print('=== AVERAGE RATING: $averageRating ===');

      setState(() {
        _productReviews[productId] = reviews;
        _averageRatings[productId] = averageRating;
      });
    } catch (e) {
      print('=== ERROR LOADING REVIEWS: ${e.runtimeType} ===');
      setState(() {
        _productReviews[productId] = [];
        _averageRatings[productId] = 0.0;
      });
    }
  }

  List<Product> get _filteredProducts {
    if (_selectedCategory == LanguageManager.translate('Tüm Kategoriler')) {
      return _products;
    }
    // Seçili kategoriyi orijinal dilde eşleştir
    String originalCategory = '';
    for (final product in _products) {
      if (LanguageManager.translate(product.category) == _selectedCategory) {
        originalCategory = product.category;
        break;
      }
    }
    return _products.where((product) => product.category == originalCategory).toList();
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LanguageManager.translate('Ürün Değerlendirmeleri')),
        backgroundColor: const Color(0xFF1877F2),
        foregroundColor: Colors.white,
        elevation: 6,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        LanguageManager.translate('Henüz ürün bulunmuyor'),
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Kategori Filtresi
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            LanguageManager.translate('Kategoriler'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _categories.map((category) {
                                final isSelected = category == _selectedCategory;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(
                                      category,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.black87,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        _selectedCategory = category;
                                      });
                                    },
                                    backgroundColor: Colors.grey[200],
                                    selectedColor: const Color(0xFF1877F2),
                                    checkmarkColor: Colors.white,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Ürünler Listesi
                    Expanded(
                      child: _buildProductsList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildProductsList() {
    final productsToShow = _filteredProducts;
    
    if (productsToShow.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.category_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '${_selectedCategory} ${LanguageManager.translate('kategorisinde ürün bulunamadı')}',
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
      padding: const EdgeInsets.all(16),
      itemCount: productsToShow.length,
      itemBuilder: (context, index) {
        final product = productsToShow[index];
        final productId = int.parse(product.id.toString());
        final reviews = _productReviews[productId] ?? [];
        final averageRating = _averageRatings[productId] ?? 0.0;
        
        print('=== PRODUCT: ${product.name}, ID: $productId, REVIEWS: ${reviews.length}, RATING: $averageRating ===');
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => _showProductReviews(product, reviews),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Ürün resmi
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.imageUrl.isNotEmpty ? AppConfig.getImageUrl(product.imageUrl) : '',
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
                  // Ürün bilgileri
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
                          LanguageManager.translate(product.category),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Yıldızlar
                            ...List.generate(5, (index) {
                              return Icon(
                                index < averageRating.floor() ? Icons.star : Icons.star_border,
                                color: index < averageRating.floor() ? Colors.amber : Colors.grey,
                                size: 16,
                              );
                            }),
                            const SizedBox(width: 8),
                            Text(
                              '${reviews.length} ${LanguageManager.translate('yorum')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Ok ikonu
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
    );
  }

  void _showProductReviews(Product product, List<dynamic> reviews) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        AppConfig.getImageUrl(product.imageUrl),
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₺${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1877F2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              // Reviews List
              Expanded(
                child: reviews.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.star_border,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              LanguageManager.translate('Bu ürün için henüz değerlendirme yok'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: reviews.length,
                        itemBuilder: (context, index) {
                          final review = reviews[index];
                          return _buildReviewCard(Map<String, dynamic>.from(review));
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    return FutureBuilder<bool>(
      future: PrivacyManager.isPrivacyEnabled(),
      builder: (context, snapshot) {
        final isPrivacyEnabled = snapshot.data ?? false;
        final userName = review['user_name'] ?? LanguageManager.translate('Anonim');
        final displayName = isPrivacyEnabled ? PrivacyManager.maskUserName(userName) : userName;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Kullanıcı adı (yıldızların üstünde)
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1877F2),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Yıldızlar
                    ...List.generate(5, (index) {
                      final rating = review['rating'];
                      final intRating = rating is int ? rating : (rating is String ? int.tryParse(rating) ?? 0 : 0);
                      return Icon(
                        index < intRating ? Icons.star : Icons.star_border,
                        color: index < intRating ? Colors.amber : Colors.grey,
                        size: 20,
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(
                      '${review['rating']}/5',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (review['comment'] != null && review['comment'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    review['comment'],
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                const SizedBox(height: 8),
                // Tarih (sağ tarafta)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _formatDate(review['created_at']),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
