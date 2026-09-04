import '../../Services/auth_http.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../Models/product.dart';
import '../../Models/seller.dart';
import '../../Services/api_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../Widgets/custom_dialog.dart';
import '../../Utils/language_manager.dart';
import '../../Utils/app_config.dart';

class SellerProductsPage extends StatefulWidget {
  final Seller seller;

  const SellerProductsPage({Key? key, required this.seller}) : super(key: key);

  @override
  State<SellerProductsPage> createState() => _SellerProductsPageState();
}

class _SellerProductsPageState extends State<SellerProductsPage> {
  List<Product> products = [];
  bool isLoading = true;

  final List<String> categories = [
    'Elektronik',
    'Kıyafet',
    'Kozmetik',
    'Mobilya',
    'Spor',
    'Oyuncak',
  ];

  @override
  void initState() {
    super.initState();
    fetchSellerProducts();
  }

  Future<void> fetchSellerProducts() async {
    try {
      final list = await ApiService.fetchProducts();
      setState(() {
        products = list
            .map((e) => Product.fromMap(e))
            .where((product) => product.sellerId == widget.seller.id)
            .toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<String?> uploadImage(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadImageUrl),
      );
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      var response = await AuthHttp.send(request);
      if (response.statusCode == 200) {
        final respStr = response.body;
        final jsonResp = jsonDecode(respStr);
        return jsonResp['url'];
      } else {
        print('Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Upload error: ${e.runtimeType}');
      return null;
    }
  }

  void _showProductDialog({Product? product}) {
    showDialog(
      context: context,
      builder: (context) => _ProductDialog(
        product: product,
        categories: categories,
        sellerId: widget.seller.id,
        onProductSaved: () {
          fetchSellerProducts();
        },
      ),
    );
  }

  void _deleteProduct(String id) async {
    await ApiService.deleteProduct(int.parse(id));
    fetchSellerProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        LanguageManager.translate('Henüz ürün eklenmemiş'),
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showProductDialog(),
                        icon: const Icon(Icons.add),
                        label: Text(LanguageManager.translate('İlk Ürününü Ekle')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    String imageUrl = product.imageUrl;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                product.imageUrl.isNotEmpty ? AppConfig.getImageUrl(product.imageUrl) : '',
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[200],
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded / 
                                              loadingProgress.expectedTotalBytes!
                                            : null,
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      color: Colors.grey,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
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
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    LanguageManager.translate(product.category),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showProductDialog(product: product);
                                } else if (value == 'delete') {
                                  _deleteProduct(product.id);
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit),
                                      const SizedBox(width: 8),
                                      Text(LanguageManager.translate('Düzenle')),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.delete, color: Colors.red),
                                      const SizedBox(width: 8),
                                      Text(LanguageManager.translate('Sil'), style: const TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  final Product? product;
  final List<String> categories;
  final int sellerId;
  final VoidCallback onProductSaved;

  const _ProductDialog({
    this.product,
    required this.categories,
    required this.sellerId,
    required this.onProductSaved,
  });

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCategory = '';
  File? _selectedImageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!.name;
      _priceController.text = widget.product!.price.toString();
      _descriptionController.text = widget.product!.description;
      // Ürünün kategorisi categories listesinde varsa kullan, yoksa ilk kategoriyi kullan
      if (widget.categories.contains(widget.product!.category)) {
        _selectedCategory = widget.product!.category;
      } else {
        _selectedCategory = widget.categories.first;
      }
    } else {
      _selectedCategory = widget.categories.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImageFile = File(image.path);
      });
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? imageUrl;
      if (_selectedImageFile != null) {
        imageUrl = await _uploadImage(_selectedImageFile!);
      } else if (widget.product != null) {
        imageUrl = widget.product!.imageUrl;
      }

      if (imageUrl == null && widget.product == null) {
        CustomDialog.showError(
          context: context,
          title: LanguageManager.translate('Hata'),
          message: LanguageManager.translate('Lütfen bir ürün fotoğrafı seçin'),
          buttonText: LanguageManager.translate('Tamam'),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Kategori güvenlik kontrolü
      if (!widget.categories.contains(_selectedCategory)) {
        _selectedCategory = widget.categories.first;
      }
      
      final productData = {
        'product_name': _nameController.text,
        'product_price': double.parse(_priceController.text),
        'product_description': _descriptionController.text,
        'product_category': _selectedCategory,
        'product_image_url': imageUrl ?? '',
        'seller_id': widget.sellerId,
      };

      if (widget.product != null) {
        await ApiService.updateProduct(int.parse(widget.product!.id), productData);
      } else {
        await ApiService.addProduct(productData);
      }

      widget.onProductSaved();
      Navigator.of(context).pop();
    } catch (e) {
      CustomDialog.showError(
        context: context,
        title: LanguageManager.translate('Hata'),
        message: LanguageManager.translate('Ürün kaydedilirken hata oluştu. Lütfen tekrar deneyin.'),
        buttonText: LanguageManager.translate('Tamam'),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(AppConfig.uploadImageUrl),
      );
      request.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      var response = await AuthHttp.send(request);
      if (response.statusCode == 200) {
        final respStr = response.body;
        final jsonResp = jsonDecode(respStr);
        return jsonResp['url'];
      } else {
        print('Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Upload error: ${e.runtimeType}');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
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
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1877F2),
                    const Color(0xFF1877F2).withOpacity(0.8),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.product != null ? Icons.edit : Icons.add_shopping_cart,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product != null 
                              ? LanguageManager.translate('Ürünü Düzenle')
                              : LanguageManager.translate('Yeni Ürün Ekle'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product != null 
                              ? LanguageManager.translate('Ürün bilgilerini güncelleyin')
                              : LanguageManager.translate('Mağazanıza yeni ürün ekleyin'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                      // Ürün Adı
                      _buildFormField(
                controller: _nameController,
                        label: LanguageManager.translate('Ürün Adı'),
                        icon: Icons.shopping_bag,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return LanguageManager.translate('Ürün adı gerekli');
                  }
                  return null;
                },
              ),
                      const SizedBox(height: 20),
                      
                      // Fiyat
                      _buildFormField(
                controller: _priceController,
                        label: LanguageManager.translate('Fiyat'),
                        icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return LanguageManager.translate('Fiyat gerekli');
                  }
                  if (double.tryParse(value) == null) {
                    return LanguageManager.translate('Geçerli bir fiyat girin');
                  }
                  return null;
                },
              ),
                      const SizedBox(height: 20),
                      
                      // Kategori
                      _buildDropdownField(),
                      const SizedBox(height: 20),
                      
                      // Açıklama
                      _buildFormField(
                controller: _descriptionController,
                        label: LanguageManager.translate('Açıklama'),
                        icon: Icons.description,
                        maxLines: 4,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return LanguageManager.translate('Açıklama gerekli');
                  }
                  return null;
                },
              ),
                      const SizedBox(height: 24),
                      
                      // Fotoğraf Seçimi
                      _buildImageSection(),
                    ],
                  ),
                ),
              ),
            ),
            
            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        LanguageManager.translate('İptal'),
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1877F2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  widget.product != null ? Icons.save : Icons.add,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.product != null 
                                      ? LanguageManager.translate('Güncelle')
                                      : LanguageManager.translate('Ekle'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
            Icon(icon, color: const Color(0xFF1877F2), size: 20),
            const SizedBox(width: 8),
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
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: label,
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.red.shade300, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

  Widget _buildDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.category, color: Color(0xFF1877F2), size: 20),
            const SizedBox(width: 8),
            Text(
              LanguageManager.translate('Kategori'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1877F2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: widget.categories.contains(_selectedCategory) ? _selectedCategory : null,
                decoration: InputDecoration(
            hintText: LanguageManager.translate('Kategori'),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                items: widget.categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
              child: Text(
                LanguageManager.translate(category),
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
      ],
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_camera, color: Color(0xFF1877F2), size: 20),
            const SizedBox(width: 8),
            Text(
              LanguageManager.translate('Ürün Fotoğrafı'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1877F2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Ana fotoğraf konteyneri
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.grey.shade50,
                Colors.grey.shade100,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.grey.shade200,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Fotoğraf alanı
              Container(
                height: 160,
                width: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: _buildImageWidget(),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Buton alanı
              _buildImageButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageWidget() {
    // Yeni seçilen fotoğraf varsa onu göster
    if (_selectedImageFile != null) {
      return Image.file(
        _selectedImageFile!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholderWidget();
        },
      );
    }
    
    // Ürün düzenleniyorsa ve mevcut fotoğraf varsa onu göster
    if (widget.product != null && 
        widget.product!.imageUrl.isNotEmpty && 
        _selectedImageFile == null) {
      return Image.network(
        AppConfig.getImageUrl(widget.product!.imageUrl),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade200,
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
          return _buildPlaceholderWidget();
        },
      );
    }
    
    // Hiç fotoğraf yoksa placeholder göster
    return _buildPlaceholderWidget();
  }

  Widget _buildPlaceholderWidget() {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_photo_alternate,
              size: 32,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            LanguageManager.translate('Fotoğraf Yok'),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageButton() {
    // Ürün düzenleniyorsa ve fotoğraf varsa "Değiştir" butonu
    if (widget.product != null && 
        widget.product!.imageUrl.isNotEmpty && 
        _selectedImageFile == null) {
      return Container(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.edit, size: 20),
          label: Text(
            LanguageManager.translate('Fotoğrafı Değiştir'),
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
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
        ),
      );
    }
    
    // Yeni fotoğraf seçildiyse "Değiştir" butonu
    if (_selectedImageFile != null) {
      return Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.edit, size: 20),
              label: Text(
                LanguageManager.translate('Değiştir'),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedImageFile = null;
                });
              },
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(
                LanguageManager.translate('Sıfırla'),
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
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // Hiç fotoğraf yoksa "Fotoğraf Seç" butonu
    return Container(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _pickImage,
        icon: const Icon(Icons.add_photo_alternate, size: 20),
        label: Text(
          LanguageManager.translate('Fotoğraf Seç'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey.shade200,
          foregroundColor: Colors.grey.shade700,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
} 