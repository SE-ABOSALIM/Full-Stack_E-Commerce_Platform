import 'dart:convert';
import 'package:http/http.dart' as http;
import '../Utils/app_config.dart';
import '../Models/session.dart';
import '../Models/seller_session.dart';
import 'auth_session.dart';

/// The API validates ownership. Route selection here only chooses the credential.
class AuthHttp {
  static bool _sellerRoute(Uri uri, String method) =>
      uri.path.startsWith('/sellers/') ||
      uri.path.startsWith('/seller_orders/') ||
      uri.path.startsWith('/seller_statistics/') ||
      uri.path.startsWith('/seller_active_orders/') ||
      uri.path == '/send-seller-email-verification-code' ||
      uri.path == '/verify-seller-email' ||
      uri.path == '/verify-seller-phone' ||
      uri.path == '/send-seller-verification-code' ||
      uri.path == '/upload-image' ||
      (method != 'GET' && uri.path.startsWith('/products'));

  static Map<String, String> headers(Uri uri, String method) {
    final base = Uri.parse(AppConfig.baseUrl);
    // Never forward credentials to an unrelated origin.
    if (uri.origin != base.origin) return {};
    final token =
        _sellerRoute(uri, method)
            ? AuthSession.sellerToken
            : AuthSession.userToken;
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Future<http.Response> _request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    final request = http.Request(method, uri);
    if (headers != null) request.headers.addAll(headers);
    if (encoding != null) request.encoding = encoding;
    if (body is String) {
      request.body = body;
    } else if (body is Map<String, String>) {
      request.bodyFields = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body != null) {
      throw ArgumentError('Unsupported request body');
    }
    return send(request);
  }

  static Future<http.Response> send(http.BaseRequest request) async {
    request.headers.addAll(headers(request.url, request.method));
    final client = http.Client();
    try {
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      if (response.statusCode == 401 &&
          request.url.path != '/users/me/password' &&
          request.url.origin == Uri.parse(AppConfig.baseUrl).origin) {
        final seller = _sellerRoute(request.url, request.method);
        await AuthSession.clear(seller ? 'seller' : 'user');
        if (seller) {
          SellerSession.currentSeller = null;
        } else {
          Session.currentUser = null;
        }
      }
      return response;
    } finally {
      client.close();
    }
  }

  static Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      _request('GET', uri, headers: headers);
  static Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) =>
      _request('DELETE', uri, headers: headers, body: body, encoding: encoding);
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _request('POST', uri, headers: headers, body: body, encoding: encoding);
  static Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) => _request('PUT', uri, headers: headers, body: body, encoding: encoding);
}
