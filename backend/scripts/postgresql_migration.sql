-- 📱 Telefon Doğrulama Sistemi PostgreSQL Migration
-- Bu dosyayı PostgreSQL veritabanınızda çalıştırın

-- 1️⃣ PhoneVerification tablosu oluştur
CREATE TABLE IF NOT EXISTS phone_verifications (
    id SERIAL PRIMARY KEY,
    phone_number VARCHAR UNIQUE NOT NULL,
    verification_code VARCHAR NOT NULL,
    is_verified VARCHAR DEFAULT 'pending',
    attempts INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP
);

-- 2️⃣ User tablosuna yeni alanlar ekle
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified VARCHAR DEFAULT 'pending';
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- 3️⃣ Seller tablosuna phone_verified alanı ekle
ALTER TABLE sellers ADD COLUMN IF NOT EXISTS phone_verified VARCHAR DEFAULT 'pending';

-- 4️⃣ Mevcut kayıtları güncelle
UPDATE users SET phone_verified = 'verified' WHERE phone_verified IS NULL;
UPDATE users SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL;
UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL;
UPDATE sellers SET phone_verified = 'verified' WHERE phone_verified IS NULL;

-- 5️⃣ Index'ler oluştur (performans için)
CREATE INDEX IF NOT EXISTS idx_phone_verifications_phone_number ON phone_verifications(phone_number);
CREATE INDEX IF NOT EXISTS idx_users_phone_verified ON users(phone_verified);
CREATE INDEX IF NOT EXISTS idx_sellers_phone_verified ON sellers(phone_verified);

-- 6️⃣ Tablo yapısını kontrol et
\d users;
\d sellers;
\d phone_verifications;

-- ✅ Migration tamamlandı!
