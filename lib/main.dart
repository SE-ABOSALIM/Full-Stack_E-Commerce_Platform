import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'splash_screen.dart';
import 'Utils/app_config.dart';
import 'Utils/language_manager.dart';
import 'Pages/user/auth/login.dart';
import 'Pages/seller/login.dart';

void main() async {
  try {
    // WidgetsBinding'i başlat
    WidgetsFlutterBinding.ensureInitialized();
    
    // Dil yöneticisini başlat
    await LanguageManager.initialize();
    
    // AppConfig'i test et
    AppConfig.testConfig();
    
    runApp(const MyApp());
  } catch (e) {
    print('Kritik hata: ${e.runtimeType}');
    runApp(const MyApp());
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Dil değişikliklerini dinle
    LanguageManager.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    // Listener'ı temizle
    LanguageManager.removeListener(() {
      setState(() {});
    });
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final currentLocale = _getCurrentLocale();
    final isRTL = currentLocale.languageCode == 'ar';
    
    return MaterialApp(
      title: 'E-Ticaret Uygulaması',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1877F2)),
        useMaterial3: true,
      ),
      // Çoklu dil desteği
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'), // Türkçe
        Locale('ar', 'SA'), // Arapça
        Locale('en', 'US'), // İngilizce
      ],
      locale: currentLocale,
      builder: (context, child) {
        return Directionality(
          textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        );
      },
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/seller/login': (context) => const SellerLoginPage(),
      },
    );
  }
  
  Locale _getCurrentLocale() {
    // Dil yöneticisinden mevcut dili al
    final languageCode = LanguageManager.currentLanguageCode;
    switch (languageCode) {
      case 'tr':
        return const Locale('tr', 'TR');
      case 'ar':
        return const Locale('ar', 'SA');
      case 'en':
        return const Locale('en', 'US');
      default:
        return const Locale('tr', 'TR');
    }
  }
}
