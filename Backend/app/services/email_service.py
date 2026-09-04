import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv

# Environment variables'ları yükle
BASE_DIR = os.path.dirname(os.path.dirname(__file__))
load_dotenv(os.path.join(BASE_DIR, "config.env"))

class EmailService:
    def __init__(self):
        # Email ayarları
        self.smtp_server = os.getenv('SMTP_SERVER', 'smtp.gmail.com')
        self.smtp_port = int(os.getenv('SMTP_PORT', '587'))
        self.sender_email = os.getenv('SENDER_EMAIL', 'your-email@gmail.com')
        self.sender_password = os.getenv('SENDER_PASSWORD', 'your-app-password')
        self.brand_name = "CepteVar"
    
    def send_verification_email(self, email: str, code: str, language: str = "tr") -> dict:
        """
        Email doğrulama kodu gönder
        
        Args:
            email: Alıcı email adresi
            code: Doğrulama kodu
            language: Dil kodu (tr, en, ar)
            
        Returns:
            dict: API yanıtı
        """
        try:
            # Dile göre mesajı al
            message_data = self.get_email_message(language, code)
            subject = message_data['subject']
            
            # Email ayarları kontrol et
            if (self.sender_email == 'your-email@gmail.com' or 
                self.sender_password == 'your-app-password'):
                print(f"⚠️ Email ayarları yapılandırılmamış. Test modunda çalışıyor...")
                
                return {
                    'success': True,
                    'message': 'Email doğrulama kodu başarıyla gönderildi (Test modu)',
                    'email': email,
                    'brand_name': self.brand_name,
                    'language': language
                }
            
            # Email oluştur
            msg = MIMEMultipart()
            msg['From'] = self.sender_email
            msg['To'] = email
            msg['Subject'] = subject
            
            # HTML içerik
            html_content = f"""
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>{subject}</title>
                <style>
                    body {{
                        font-family: Arial, sans-serif;
                        line-height: 1.6;
                        color: #333;
                        max-width: 600px;
                        margin: 0 auto;
                        padding: 20px;
                    }}
                    .header {{
                        background-color: #1877F2;
                        color: white;
                        padding: 20px;
                        text-align: center;
                        border-radius: 10px 10px 0 0;
                    }}
                    .content {{
                        background-color: #f9f9f9;
                        padding: 30px;
                        border-radius: 0 0 10px 10px;
                    }}
                    .code {{
                        background-color: #1877F2;
                        color: white;
                        font-size: 24px;
                        font-weight: bold;
                        padding: 15px;
                        text-align: center;
                        border-radius: 8px;
                        margin: 20px 0;
                        letter-spacing: 3px;
                    }}
                    .footer {{
                        margin-top: 30px;
                        padding-top: 20px;
                        border-top: 1px solid #ddd;
                        font-size: 12px;
                        color: #666;
                        text-align: center;
                    }}
                </style>
            </head>
            <body>
                <div class="header">
                    <h1>{self.brand_name}</h1>
                    <p>Email Doğrulama</p>
                </div>
                <div class="content">
                    <h2>{message_data['title']}</h2>
                    <p>{message_data['description']}</p>
                    <div class="code">{code}</div>
                    <p>{message_data['warning']}</p>
                    <p>{message_data['expiry']}</p>
                </div>
                <div class="footer">
                    <p>Bu email {self.brand_name} uygulaması tarafından gönderilmiştir.</p>
                    <p>Bu kodu kimseyle paylaşmayın.</p>
                </div>
            </body>
            </html>
            """
            
            msg.attach(MIMEText(html_content, 'html'))
            
            # Email gönder
            server = smtplib.SMTP(self.smtp_server, self.smtp_port)
            server.starttls()
            server.login(self.sender_email, self.sender_password)
            
            text = msg.as_string()
            server.sendmail(self.sender_email, email, text)
            server.quit()
            
            print("Email başarıyla gönderildi")
            
            return {
                'success': True,
                'message': 'Email doğrulama kodu başarıyla gönderildi',
                'email': email,
                'brand_name': self.brand_name,
                'language': language
            }
            
        except Exception as e:
            print(f"❌ Email gönderilirken hata: {type(e).__name__}")
            return {
                'success': False,
                'message': f'Email gönderilirken hata oluştu: {str(e)}',
                'email': email,
                'brand_name': self.brand_name,
                'language': language
            }
    
    def get_email_message(self, language: str, code: str) -> dict:
        """
        Dile göre email mesajını döndür
        
        Args:
            language: Dil kodu (tr, en, ar)
            code: Doğrulama kodu
            
        Returns:
            dict: Mesaj bilgileri
        """
        lang = language.lower() if language else "tr"
        
        messages = {
            "tr": {
                "subject": f"{self.brand_name} - Email Doğrulama Kodu",
                "title": "Email Adresinizi Doğrulayın",
                "description": "Hesabınızı doğrulamak için aşağıdaki kodu kullanın:",
                "warning": "Bu kodu kimseyle paylaşmayın. Güvenliğiniz için önemlidir.",
                "expiry": "Bu kod 5 dakika geçerlidir."
            },
            "en": {
                "subject": f"{self.brand_name} - Email Verification Code",
                "title": "Verify Your Email Address",
                "description": "Use the code below to verify your account:",
                "warning": "Do not share this code with anyone. It's important for your security.",
                "expiry": "This code is valid for 5 minutes."
            },
            "ar": {
                "subject": f"{self.brand_name} - رمز التحقق من البريد الإلكتروني",
                "title": "تحقق من عنوان بريدك الإلكتروني",
                "description": "استخدم الرمز أدناه للتحقق من حسابك:",
                "warning": "لا تشارك هذا الرمز مع أي شخص. إنه مهم لأمانك.",
                "expiry": "هذا الرمز صالح لمدة 5 دقائق."
            }
        }
        
        return messages.get(lang, messages["tr"])

# Global email servisi instance'ı
email_service = EmailService()
