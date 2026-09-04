import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../Models/User.dart';
import '../Models/address.dart';
import '../Models/credit_card.dart';
import '../Models/product.dart';
import '../Models/order.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'ecommerce.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nameSurname TEXT NOT NULL,
        password TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phoneNumber TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE Address(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        city TEXT,
        district TEXT,
        neighbourhood TEXT,
        street_name TEXT,
        building_number INTEGER,
        apartment_number INTEGER,
        address_owner_name TEXT,
        address_owner_surname TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE "Credit-Card"(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        card_name TEXT,
        card_number TEXT,
        card_outdate NUMERIC,
        card_cvv INTEGER,
        card_balance REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE Products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_name TEXT,
        product_price REAL,
        product_description TEXT,
        product_category TEXT,
        product_image TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE "Users-Address"(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        address_id INTEGER,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(address_id) REFERENCES Address(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE "Users-Credit-Card"(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        credit_card_id INTEGER,
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (credit_card_id) REFERENCES "Credit-Card"(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE "Order" (
        id	INTEGER PRIMARY KEY AUTOINCREMENT,
        order_code	TEXT,
        order_created_date	TEXT,
        order_estimated_delivery	TEXT,
        order_cargo_company	TEXT,
        order_address	INTEGER,
        FOREIGN KEY(order_address) REFERENCES Address(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE "Users_Order"(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        product_id INTEGER,
        order_id INTEGER,
        FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES Products(id) ON DELETE CASCADE,
        FOREIGN KEY(order_id) REFERENCES "Order"(id) ON DELETE CASCADE
      )
    ''');
  }

  // Kullanıcı ekleme
  Future<int> insertUser(User user) async {
    final db = await database;
    return await db.insert('users', user.toMap());
  }

  // Kullanıcı güncelleme (email ile)
  Future<int> updateUser(User user) async {
    final db = await database;
    return await db.update(
      'users',
      user.toMap(),
      where: 'email = ?',
      whereArgs: [user.email],
    );
  }

  // Kullanıcı silme (email ile)
  Future<int> deleteUser(String email) async {
    final db = await database;
    return await db.delete(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  // Tüm kullanıcıları getirme
  Future<List<User>> getAllUsers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users');
    return List.generate(maps.length, (i) {
      return User(
        id: maps[i]['id'],
        nameSurname: maps[i]['nameSurname'],
        password: maps[i]['password'],
        email: maps[i]['email'],
        phoneNumber: maps[i]['phoneNumber'],
      );
    });
  }

  // Email ile kullanıcı arama
  Future<User?> getUserByEmail(String email) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (maps.isNotEmpty) {
      return User(
        id: maps[0]['id'],
        nameSurname: maps[0]['nameSurname'],
        password: maps[0]['password'],
        email: maps[0]['email'],
        phoneNumber: maps[0]['phoneNumber'],
      );
    }
    return null;
  }

  // Kullanıcı girişi kontrolü
  Future<User?> loginUser(String email, String password) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'email = ? AND password = ?',
      whereArgs: [email, password],
    );

    if (maps.isNotEmpty) {
      return User(
        id: maps[0]['id'],
        nameSurname: maps[0]['nameSurname'],
        password: maps[0]['password'],
        email: maps[0]['email'],
        phoneNumber: maps[0]['phoneNumber'],
      );
    }
    return null;
  }

  // Adres ekleme
  Future<int> insertAddress(Address address) async {
    final db = await database;
    return await db.insert('Address', address.toMap());
  }

  // Adresleri listeleme (kullanıcıya göre)
  Future<List<Address>> getAddressesByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT Address.* FROM Address
      INNER JOIN "Users-Address" ON Address.id = "Users-Address".address_id
      WHERE "Users-Address".user_id = ?
    ''', [userId]);
    return List.generate(maps.length, (i) => Address.fromMap(maps[i]));
  }

  // Adres silme
  Future<int> deleteAddress(int addressId) async {
    final db = await database;
    return await db.delete('Address', where: 'id = ?', whereArgs: [addressId]);
  }

  // Kullanıcı-adres ilişkisi ekleme
  Future<int> insertUserAddress(int userId, int addressId) async {
    final db = await database;
    return await db.insert('"Users-Address"', {
      'user_id': userId,
      'address_id': addressId,
    });
  }

  // Kredi kartı ekleme
  Future<int> insertCreditCard(CreditCard card) async {
    print('DatabaseHelper: Kart ekleme işlemi başlatılıyor...');
    
    final db = await database;
    try {
      final id = await db.insert('"Credit-Card"', card.toMap());
      print('DatabaseHelper: Kart başarıyla eklendi. ID: $id');
      return id;
    } catch (e) {
      print('DatabaseHelper HATA: Kart eklenirken hata oluştu: ${e.runtimeType}');
      return -1;
    }
  }

  // Kredi kartlarını listeleme (kullanıcıya göre)
  Future<List<CreditCard>> getCreditCardsByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT "Credit-Card".* FROM "Credit-Card"
      INNER JOIN "Users-Credit-Card" ON "Credit-Card".id = "Users-Credit-Card".credit_card_id
      WHERE "Users-Credit-Card".user_id = ?
    ''', [userId]);
    return List.generate(maps.length, (i) => CreditCard.fromMap(maps[i]));
  }

  // Kredi kartı silme
  Future<int> deleteCreditCard(int cardId) async {
    final db = await database;
    return await db.delete('"Credit-Card"', where: 'id = ?', whereArgs: [cardId]);
  }

  // Kullanıcı-kredi kartı ilişkisi ekleme
  Future<int> insertUserCreditCard(int userId, int cardId) async {
    print('DatabaseHelper: Kullanıcı-kart ilişkisi ekleniyor...');
    print('DatabaseHelper: User ID: $userId, Card ID: $cardId');
    
    final db = await database;
    try {
      final id = await db.insert('"Users-Credit-Card"', {
        'user_id': userId,
        'credit_card_id': cardId,
      });
      print('DatabaseHelper: Kullanıcı-kart ilişkisi başarıyla eklendi. ID: $id');
      return id;
    } catch (e) {
      print('DatabaseHelper HATA: Kullanıcı-kart ilişkisi eklenirken hata oluştu: ${e.runtimeType}');
      return -1;
    }
  }

  // Adres güncelleme
  Future<int> updateAddress(Address address) async {
    final db = await database;
    return await db.update(
      'Address',
      address.toMap(),
      where: 'id = ?',
      whereArgs: [address.id],
    );
  }

  // Kredi kartı güncelleme
  Future<int> updateCreditCard(CreditCard card) async {
    final db = await database;
    return await db.update(
      '"Credit-Card"',
      card.toMap(),
      where: 'id = ?',
      whereArgs: [card.id],
    );
  }

  // Ürün ekleme
  Future<int> insertProduct(Product product) async {
    final db = await database;
    return await db.insert('Products', {
      'product_name': product.name,
      'product_price': product.price,
      'product_description': product.description,
      'product_category': product.category,
      'product_image': product.imageUrl,
    });
  }

  // Ürünleri listeleme
  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('Products');
    return List.generate(maps.length, (i) => Product(
      id: maps[i]['id'].toString(),
      name: maps[i]['product_name'],
      price: maps[i]['product_price'] is int ? (maps[i]['product_price'] as int).toDouble() : maps[i]['product_price'],
      imageUrl: maps[i]['product_image'] ?? '',
      description: maps[i]['product_description'],
      category: maps[i]['product_category'],
    ));
  }

  // Ürün silme
  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('Products', where: 'id = ?', whereArgs: [id]);
  }

  // Ürün güncelleme
  Future<int> updateProduct(Product product) async {
    final db = await database;
    return await db.update(
      'Products',
      {
        'product_name': product.name,
        'product_price': product.price,
        'product_description': product.description,
        'product_category': product.category,
        'product_image': product.imageUrl,
      },
      where: 'id = ?',
      whereArgs: [int.tryParse(product.id) ?? product.id],
    );
  }

  // Sipariş ekleme
  Future<int> insertOrder(Order order) async {
    final db = await database;
    return await db.insert('Order', order.toMap());
  }

  // Kullanıcı-sipariş-ürün ilişkisi ekleme
  Future<int> insertUserOrder(int userId, int productId, int orderId) async {
    final db = await database;
    return await db.insert('Users_Order', {
      'user_id': userId,
      'product_id': productId,
      'order_id': orderId,
    });
  }

  // Kullanıcının siparişlerini getirme
  Future<List<Order>> getOrdersByUserId(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT o.* FROM "Order" o
      INNER JOIN "Users_Order" uo ON o.id = uo.order_id
      WHERE uo.user_id = ?
      ORDER BY o.id DESC
    ''', [userId]);
    return List.generate(maps.length, (i) => Order.fromMap(maps[i]));
  }

  // Siparişteki ürünleri getir
  Future<List<Product>> getProductsByOrderId(int orderId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT p.* FROM Products p
      INNER JOIN "Users_Order" uo ON p.id = uo.product_id
      WHERE uo.order_id = ?
    ''', [orderId]);
    return List.generate(maps.length, (i) => Product(
      id: maps[i]['id'].toString(),
      name: maps[i]['product_name'],
      price: maps[i]['product_price'] is int ? (maps[i]['product_price'] as int).toDouble() : maps[i]['product_price'],
      imageUrl: maps[i]['product_image'] ?? '',
      description: maps[i]['product_description'],
      category: maps[i]['product_category'],
    ));
  }
}
