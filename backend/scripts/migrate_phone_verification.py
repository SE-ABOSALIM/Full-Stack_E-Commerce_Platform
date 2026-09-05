#!/usr/bin/env python3
"""
Telefon doğrulama sistemi için veritabanı migration script'i
PostgreSQL için uygun veri tipleri kullanılıyor
"""

import sqlite3
import os
from datetime import datetime

def check_database_type():
    """Veritabanı türünü kontrol et"""
    print("🔍 Veritabanı türü kontrol ediliyor...")
    
    # SQLite dosyası var mı kontrol et
    if os.path.exists("database.db"):
        print("✅ SQLite veritabanı bulundu")
        return "sqlite"
    else:
        print("⚠️ SQLite veritabanı bulunamadı")
        print("💡 PostgreSQL kullanılıyor olabilir")
        return "postgresql"

def migrate_sqlite():
    """SQLite veritabanı için migration"""
    print("\n📱 SQLite Migration Başlatılıyor...")
    
    try:
        conn = sqlite3.connect("database.db")
        cursor = conn.cursor()
        
        # 1. PhoneVerification tablosu oluştur
        print("1️⃣ PhoneVerification tablosu oluşturuluyor...")
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS phone_verifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                phone_number TEXT UNIQUE NOT NULL,
                verification_code TEXT NOT NULL,
                is_verified TEXT DEFAULT 'pending',
                attempts INTEGER DEFAULT 0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                expires_at TIMESTAMP
            )
        """)
        print("✅ PhoneVerification tablosu oluşturuldu")
        
        # 2. User tablosuna yeni alanlar ekle
        print("2️⃣ User tablosuna yeni alanlar ekleniyor...")
        
        # phone_verified alanı ekle
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN phone_verified TEXT DEFAULT 'pending'")
            print("✅ phone_verified alanı eklendi")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print("ℹ️ phone_verified alanı zaten mevcut")
            else:
                print(f"⚠️ phone_verified alanı eklenirken hata: {e}")
        
        # created_at alanı ekle
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            print("✅ created_at alanı eklendi")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print("ℹ️ created_at alanı zaten mevcut")
            else:
                print(f"⚠️ created_at alanı eklenirken hata: {e}")
        
        # updated_at alanı ekle
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP")
            print("✅ updated_at alanı eklendi")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print("ℹ️ updated_at alanı zaten mevcut")
            else:
                print(f"⚠️ updated_at alanı eklenirken hata: {e}")
        
        # 3. Seller tablosuna phone_verified alanı ekle
        print("3️⃣ Seller tablosuna phone_verified alanı ekleniyor...")
        try:
            cursor.execute("ALTER TABLE sellers ADD COLUMN phone_verified TEXT DEFAULT 'pending'")
            print("✅ phone_verified alanı eklendi")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print("ℹ️ phone_verified alanı zaten mevcut")
            else:
                print(f"⚠️ phone_verified alanı eklenirken hata: {e}")
        
        # 4. Mevcut kayıtları güncelle
        print("4️⃣ Mevcut kayıtlar güncelleniyor...")
        
        # Users tablosundaki mevcut kayıtları güncelle
        cursor.execute("UPDATE users SET phone_verified = 'verified' WHERE phone_verified IS NULL")
        cursor.execute("UPDATE users SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL")
        cursor.execute("UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL")
        print("✅ Users tablosu güncellendi")
        
        # Sellers tablosundaki mevcut kayıtları güncelle
        cursor.execute("UPDATE sellers SET phone_verified = 'verified' WHERE phone_verified IS NULL")
        print("✅ Sellers tablosu güncellendi")
        
        # Değişiklikleri kaydet
        conn.commit()
        print("\n🎉 SQLite migration başarıyla tamamlandı!")
        
        # Tablo yapısını göster
        print("\n📊 Tablo Yapısı:")
        cursor.execute("PRAGMA table_info(users)")
        user_columns = cursor.fetchall()
        print("Users tablosu:")
        for col in user_columns:
            print(f"  - {col[1]} ({col[2]})")
        
        cursor.execute("PRAGMA table_info(sellers)")
        seller_columns = cursor.fetchall()
        print("\nSellers tablosu:")
        for col in seller_columns:
            print(f"  - {col[1]} ({col[2]})")
        
        cursor.execute("PRAGMA table_info(phone_verifications)")
        phone_columns = cursor.fetchall()
        print("\nPhoneVerifications tablosu:")
        for col in phone_columns:
            print(f"  - {col[1]} ({col[2]})")
        
    except Exception as e:
        print(f"❌ Migration hatası: {e}")
        conn.rollback()
    finally:
        conn.close()

def migrate_postgresql():
    """PostgreSQL veritabanı için migration"""
    print("\n📱 PostgreSQL Migration Başlatılıyor...")
    print("💡 PostgreSQL için aşağıdaki SQL komutlarını çalıştırın:")
    
    print("\n1️⃣ PhoneVerification tablosu oluştur:")
    print("""
    CREATE TABLE IF NOT EXISTS phone_verifications (
        id SERIAL PRIMARY KEY,
        phone_number VARCHAR UNIQUE NOT NULL,
        verification_code VARCHAR NOT NULL,
        is_verified VARCHAR DEFAULT 'pending',
        attempts INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP
    );
    """)
    
    print("2️⃣ User tablosuna yeni alanlar ekle:")
    print("""
    ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified VARCHAR DEFAULT 'pending';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
    """)
    
    print("3️⃣ Seller tablosuna phone_verified alanı ekle:")
    print("""
    ALTER TABLE sellers ADD COLUMN IF NOT EXISTS phone_verified VARCHAR DEFAULT 'pending';
    """)
    
    print("4️⃣ Mevcut kayıtları güncelle:")
    print("""
    UPDATE users SET phone_verified = 'verified' WHERE phone_verified IS NULL;
    UPDATE users SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL;
    UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL;
    UPDATE sellers SET phone_verified = 'verified' WHERE phone_verified IS NULL;
    """)
    
    print("5️⃣ Index'ler oluştur:")
    print("""
    CREATE INDEX IF NOT EXISTS idx_phone_verifications_phone_number ON phone_verifications(phone_number);
    CREATE INDEX IF NOT EXISTS idx_users_phone_verified ON users(phone_verified);
    CREATE INDEX IF NOT EXISTS idx_sellers_phone_verified ON sellers(phone_verified);
    """)

def main():
    """Ana migration fonksiyonu"""
    print("🚀 Telefon Doğrulama Sistemi Migration Script'i")
    print("=" * 50)
    
    db_type = check_database_type()
    
    if db_type == "sqlite":
        migrate_sqlite()
    else:
        migrate_postgresql()
    
    print("\n📋 Sonraki Adımlar:")
    print("1. API'yi yeniden başlatın")
    print("2. Test script'ini çalıştırın")
    print("3. Telefon doğrulama sistemini test edin")
    print("\n✨ Migration tamamlandı!")

if __name__ == "__main__":
    main()
