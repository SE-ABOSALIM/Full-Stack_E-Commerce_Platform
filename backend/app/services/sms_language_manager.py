#!/usr/bin/env python3
"""
Çok dilli SMS mesaj yöneticisi
Marka adı ile SMS gönderimi için dil desteği
"""

class SMSLanguageManager:
    def __init__(self):
        # Marka adı (gönderen olarak görünecek)
        self.brand_name = "CepteVar"
        
        # Desteklenen diller
        self.supported_languages = ["tr", "en", "ar"]
        
        # Varsayılan dil
        self.default_language = "tr"
    
    def get_sms_message(self, language: str, code: str) -> dict:
        """
        Dile göre SMS mesajını döndür
        
        Args:
            language: Dil kodu (tr, en, ar)
            code: Doğrulama kodu
            
        Returns:
            dict: Mesaj ve gönderen bilgisi
        """
        # Dil kodunu normalize et
        lang = language.lower() if language else self.default_language
        
        # Desteklenmeyen dil için varsayılan dili kullan
        if lang not in self.supported_languages:
            lang = self.default_language
        
        # Dile göre mesaj şablonları (basitleştirilmiş)
        messages = {
            "tr": {
                "message": f"CepteVar doğrulama kodu: {code}",
                "sender": self.brand_name
            },
            "en": {
                "message": f"CepteVar verification code: {code}",
                "sender": self.brand_name
            },
            "ar": {
                "message": f"CepteVar رمز التحقق: {code}",
                "sender": self.brand_name
            }
        }
        
        return messages[lang]
    
    def get_welcome_message(self, language: str, user_name: str = "") -> dict:
        """
        Dile göre hoş geldin mesajını döndür
        
        Args:
            language: Dil kodu (tr, en, ar)
            user_name: Kullanıcı adı (opsiyonel)
            
        Returns:
            dict: Mesaj ve gönderen bilgisi
        """
        lang = language.lower() if language else self.default_language
        
        if lang not in self.supported_languages:
            lang = self.default_language
        
        welcome_messages = {
            "tr": {
                "message": f"Hoş geldiniz! {self.brand_name} uygulamasına başarıyla kayıt oldunuz. Güvenli alışverişler dileriz!",
                "sender": self.brand_name
            },
            "en": {
                "message": f"Welcome! You have successfully registered to {self.brand_name} app. We wish you safe shopping!",
                "sender": self.brand_name
            },
            "ar": {
                "message": f"مرحباً! لقد سجلت بنجاح في تطبيق {self.brand_name}. نتمنى لك تسوقاً آمناً!",
                "sender": self.brand_name
            }
        }
        
        return welcome_messages[lang]
    
    def get_order_status_message(self, language: str, order_number: str, status: str) -> dict:
        """
        Dile göre sipariş durumu mesajını döndür
        
        Args:
            language: Dil kodu (tr, en, ar)
            order_number: Sipariş numarası
            status: Sipariş durumu
            
        Returns:
            dict: Mesaj ve gönderen bilgisi
        """
        lang = language.lower() if language else self.default_language
        
        if lang not in self.supported_languages:
            lang = self.default_language
        
        # Durum mesajları
        status_messages = {
            "tr": {
                "confirmed": "onaylandı",
                "shipped": "kargoya verildi",
                "delivered": "teslim edildi",
                "cancelled": "iptal edildi"
            },
            "en": {
                "confirmed": "confirmed",
                "shipped": "shipped",
                "delivered": "delivered",
                "cancelled": "cancelled"
            },
            "ar": {
                "confirmed": "تم التأكيد",
                "shipped": "تم الشحن",
                "delivered": "تم التسليم",
                "cancelled": "تم الإلغاء"
            }
        }
        
        # Ana mesaj şablonları
        order_messages = {
            "tr": {
                "message": f"Sipariş #{order_number} {status_messages[lang].get(status, status)}. {self.brand_name} uygulamasından takip edebilirsiniz.",
                "sender": self.brand_name
            },
            "en": {
                "message": f"Order #{order_number} has been {status_messages[lang].get(status, status)}. You can track it from {self.brand_name} app.",
                "sender": self.brand_name
            },
            "ar": {
                "message": f"الطلب رقم #{order_number} {status_messages[lang].get(status, status)}. يمكنك تتبعه من تطبيق {self.brand_name}.",
                "sender": self.brand_name
            }
        }
        
        return order_messages[lang]
    
    def get_promotional_message(self, language: str, discount: str = "", valid_until: str = "") -> dict:
        """
        Dile göre promosyon mesajını döndür
        
        Args:
            language: Dil kodu (tr, en, ar)
            discount: İndirim miktarı
            valid_until: Geçerlilik tarihi
            
        Returns:
            dict: Mesaj ve gönderen bilgisi
        """
        lang = language.lower() if language else self.default_language
        
        if lang not in self.supported_languages:
            lang = self.default_language
        
        promo_messages = {
            "tr": {
                "message": f"🎉 {self.brand_name} özel fırsatı! {discount} indirim. Bu fırsat {valid_until} tarihine kadar geçerli. Hemen alışverişe başlayın!",
                "sender": self.brand_name
            },
            "en": {
                "message": f"🎉 {self.brand_name} special offer! {discount} discount. This offer is valid until {valid_until}. Start shopping now!",
                "sender": self.brand_name
            },
            "ar": {
                "message": f"🎉 عرض خاص من {self.brand_name}! خصم {discount}. هذا العرض صالح حتى {valid_until}. ابدأ التسوق الآن!",
                "sender": self.brand_name
            }
        }
        
        return promo_messages[lang]
    
    def get_language_from_phone(self, phone_number: str) -> str:
        """
        Telefon numarasından dil tahmini yap
        
        Args:
            phone_number: Telefon numarası
            
        Returns:
            str: Tahmin edilen dil kodu
        """
        # Türkiye numaraları için Türkçe
        if phone_number.startswith('+90') or phone_number.startswith('0'):
            return "tr"
        # ABD numaraları için İngilizce
        elif phone_number.startswith('+1'):
            return "en"
        # Arap ülkeleri için Arapça
        elif phone_number.startswith('+966') or phone_number.startswith('+971') or phone_number.startswith('+973'):
            return "ar"
        # Varsayılan olarak İngilizce
        else:
            return "en"
    
    def get_supported_languages(self) -> list:
        """Desteklenen dilleri döndür"""
        return self.supported_languages
    
    def is_language_supported(self, language: str) -> bool:
        """Dilin desteklenip desteklenmediğini kontrol et"""
        return language.lower() in self.supported_languages

# Global SMS dil yöneticisi instance'ı
sms_language_manager = SMSLanguageManager()
