import os
from twilio.rest import Client
from typing import Optional
from dotenv import load_dotenv
from app.services.sms_language_manager import sms_language_manager

# Environment variables'ları yükle
BASE_DIR = os.path.dirname(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, "config.env"))

class TwilioSMS:
    def __init__(self):
        # Twilio API bilgileri
        self.account_sid = os.getenv('TWILIO_ACCOUNT_SID', 'your_account_sid')
        self.auth_token = os.getenv('TWILIO_AUTH_TOKEN', 'your_auth_token')
        self.from_number = os.getenv('TWILIO_FROM_NUMBER', 'your_twilio_number')
        
        # Marka adı (Alphanumeric Sender ID olarak kullanılacak)
        self.brand_name = sms_language_manager.brand_name
        
        # Twilio client'ı oluştur
        self.client = Client(self.account_sid, self.auth_token)
    
    def send_sms(self, phone_number: str, message: str, language: str = None) -> dict:
        """
        Global SMS gönder (telefon numarası ile)
        
        Args:
            phone_number: Telefon numarası (ülke kodu ile: +905321234567)
            message: Gönderilecek mesaj
            language: Dil kodu (tr, en, ar) - None ise telefon numarasından tahmin edilir
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dil belirtilmemişse telefon numarasından tahmin et
            if not language:
                language = sms_language_manager.get_language_from_phone(phone_number)
            
            print(f"📱 SMS gönderiliyor:")
            print(f"   🌍 Language: {language}")
            
            # Telefon numarası ile SMS gönder
            message_obj = self.client.messages.create(
                body=message,
                from_=self.from_number,  # Telefon numarası kullan
                to=phone_number
            )
            
            print(f"✅ SMS gönderildi:")
            print(f"   🆔 Message ID: {message_obj.sid}")
            print(f"   📊 Status: {message_obj.status}")
            print(f"   💰 Price: {message_obj.price}")
            
            return {
                'success': True,
                'message': 'SMS başarıyla gönderildi',
                'message_id': message_obj.sid,
                'status': message_obj.status,
                'price': message_obj.price,
                'brand_name': self.brand_name,
                'sender_id': self.from_number,
                'language': language
            }
            
        except Exception as e:
            print(f"❌ SMS gönderilirken hata: {type(e).__name__}")
            return {
                'success': False,
                'message': f'SMS gönderilirken hata oluştu: {str(e)}',
                'error_code': getattr(e, 'code', None),
                'brand_name': self.brand_name,
                'language': language
            }
    
    def send_verification_sms(self, phone_number: str, code: str, language: str = None) -> dict:
        """
        Doğrulama kodu SMS'i gönder (çok dilli, Alphanumeric Sender ID ile)
        
        Args:
            phone_number: Telefon numarası
            code: Doğrulama kodu
            language: Dil kodu (tr, en, ar)
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dile göre mesajı al
            sms_data = sms_language_manager.get_sms_message(language, code)
            message = sms_data['message']
            
            # SMS gönder
            result = self.send_sms(phone_number, message, language)
            
            if result['success']:
                result['brand_name'] = sms_data['sender']
                result['message_type'] = 'verification'
            
            return result
            
        except Exception as e:
            return {
                'success': False,
                'message': f'Doğrulama SMS gönderilirken hata: {str(e)}',
                'brand_name': self.brand_name,
                'language': language
            }
    
    def send_welcome_sms(self, phone_number: str, language: str = None, user_name: str = "") -> dict:
        """
        Hoş geldin SMS'i gönder (çok dilli)
        
        Args:
            phone_number: Telefon numarası
            language: Dil kodu (tr, en, ar)
            user_name: Kullanıcı adı (opsiyonel)
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dile göre mesajı al
            sms_data = sms_language_manager.get_welcome_message(language, user_name)
            message = sms_data['message']
            
            # SMS gönder
            result = self.send_sms(phone_number, message, language)
            
            if result['success']:
                result['brand_name'] = sms_data['sender']
                result['message_type'] = 'welcome'
            
            return result
            
        except Exception as e:
            return {
                'success': False,
                'message': f'Hoş geldin SMS gönderilirken hata: {str(e)}',
                'brand_name': self.brand_name,
                'language': language
            }
    
    def send_order_status_sms(self, phone_number: str, order_number: str, status: str, language: str = None) -> dict:
        """
        Sipariş durumu SMS'i gönder (çok dilli)
        
        Args:
            phone_number: Telefon numarası
            order_number: Sipariş numarası
            status: Sipariş durumu
            language: Dil kodu (tr, en, ar)
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dile göre mesajı al
            sms_data = sms_language_manager.get_order_status_message(language, order_number, status)
            message = sms_data['message']
            
            # SMS gönder
            result = self.send_sms(phone_number, message, language)
            
            if result['success']:
                result['brand_name'] = sms_data['sender']
                result['message_type'] = 'order_status'
            
            return result
            
        except Exception as e:
            return {
                'success': False,
                'message': f'Sipariş durumu SMS gönderilirken hata: {str(e)}',
                'brand_name': self.brand_name,
                'language': language
            }
    
    def send_promotional_sms(self, phone_number: str, discount: str, valid_until: str, language: str = None) -> dict:
        """
        Promosyon SMS'i gönder (çok dilli)
        
        Args:
            phone_number: Telefon numarası
            discount: İndirim miktarı
            valid_until: Geçerlilik tarihi
            language: Dil kodu (tr, en, ar)
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dile göre mesajı al
            sms_data = sms_language_manager.get_promotional_message(language, discount, valid_until)
            message = sms_data['message']
            
            # SMS gönder
            result = self.send_sms(phone_number, message, language)
            
            if result['success']:
                result['brand_name'] = sms_data['sender']
                result['message_type'] = 'promotional'
            
            return result
            
        except Exception as e:
            return {
                'success': False,
                'message': f'Promosyon SMS gönderilirken hata: {str(e)}',
                'brand_name': self.brand_name,
                'language': language
            }
    
    def get_balance(self) -> dict:
        """
        Twilio hesap bakiyesini sorgula
        """
        try:
            # Hesap bilgilerini al
            account = self.client.api.accounts(self.account_sid).fetch()
            
            return {
                'success': True,
                'balance': float(account.balance),
                'currency': account.currency,
                'message': f'Hesap bakiyesi: {account.balance} {account.currency}',
                'brand_name': self.brand_name
            }
            
        except Exception as e:
            return {
                'success': False,
                'message': f'Bakiye sorgulanamadı: {str(e)}',
                'brand_name': self.brand_name
            }
    
    def get_supported_languages(self) -> list:
        """Desteklenen dilleri döndür"""
        return sms_language_manager.get_supported_languages()
    
    def is_language_supported(self, language: str) -> bool:
        """Dilin desteklenip desteklenmediğini kontrol et"""
        return sms_language_manager.is_language_supported(language)
    


# Global Twilio SMS servisi instance'ı
twilio_sms_service = TwilioSMS()
