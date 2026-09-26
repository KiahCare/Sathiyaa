import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../services/device_info.dart';

/// An error carrying the backend's own `{error:{code,message}}` envelope, so
/// the UI can show the server's wording rather than a generic failure.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);

  @override
  String toString() => message;
}

/// Thin JSON/JWT wrapper over `package:http`. Everything the app sends carries
/// the device id (the backend writes it into every audit_log row) and, once
/// signed in, the bearer token.
class ApiClient {
  /// The shared key a public deployment requires on every call.
  ///
  /// Baked in at build time:
  ///   flutter build apk --dart-define=API_ACCESS_KEY=...
  ///
  /// Empty by default, so a local server with no key configured behaves
  /// exactly as before. Anyone who unpacks the APK can read it — that is
  /// understood and it is not the point. It keeps an endpoint that hands back
  /// one-time codes off the open internet while no SMS provider is wired up.
  static const accessKey = String.fromEnvironment('API_ACCESS_KEY');

  final String baseUrl;
  String? token;
  String deviceId;

  ApiClient(this.baseUrl, {this.deviceId = 'sathiyaa-provider-app'});

  static const _timeout = Duration(seconds: 20);

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'X-Device-Id': deviceId,
        // Make, model, OS and app version, so the console can say which
        // handset an account was on rather than only that it was "a device".
        ...DeviceInfo.headers,
        if (accessKey.isNotEmpty) 'X-Sathiyaa-Key': accessKey,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.map((k, v) => MapEntry(k, '$v'))
      ?..removeWhere((_, v) => v.isEmpty || v == 'null');
    return Uri.parse('$baseUrl$path').replace(queryParameters: cleaned?.isEmpty ?? true ? null : cleaned);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => http.post(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => http.put(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, [Object? body]) =>
      _send(() => http.patch(_uri(path), headers: _headers(), body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path, [Object? body]) => _send(() => http.delete(
        _uri(path),
        headers: _headers(),
        body: body == null ? null : jsonEncode(body),
      ));

  /// Uploads a photo or document and returns the URL the server will serve it
  /// from. That URL is what goes into the `*_url` columns — the app never
  /// stores a local file path against a remote record.
  Future<String> uploadFile(String filePath, {String category = 'photo'}) async {
    final file = File(filePath);
    if (!file.existsSync()) throw ApiException(0, 'NO_FILE', 'That file is no longer on this device.');

    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/uploads?category=$category'))
      ..headers.addAll({
        'X-Device-Id': deviceId,
        ...DeviceInfo.headers,
        if (accessKey.isNotEmpty) 'X-Sathiyaa-Key': accessKey,
        if (token != null) 'Authorization': 'Bearer $token',
      })
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        filePath,
        // fromPath does not sniff the type; without this every upload arrives
        // as application/octet-stream and the server rejects it.
        contentType: _mediaTypeFor(filePath),
      ));

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ApiException(0, 'NETWORK', 'Could not upload to $baseUrl: $e');
    }
    final res = await http.Response.fromStream(streamed);

    dynamic parsed;
    try {
      parsed = jsonDecode(res.body);
    } catch (_) {
      parsed = null;
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = (parsed is Map && parsed['error'] is Map) ? parsed['error'] as Map : null;
      throw ApiException(
        res.statusCode,
        (err?['code'] ?? 'UPLOAD_FAILED').toString(),
        (err?['message'] ?? 'Upload failed (${res.statusCode})').toString(),
      );
    }
    return '${(parsed as Map)['url']}';
  }

  Future<dynamic> _send(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(_timeout);
    } on SocketException {
      throw ApiException(0, 'NETWORK',
          'Cannot reach the server at $baseUrl. Check the address, that the API is running, and that the phone is on the same network.');
    } on HttpException {
      throw ApiException(0, 'NETWORK', 'The connection to $baseUrl failed.');
    } catch (e) {
      throw ApiException(0, 'NETWORK', 'The request to $baseUrl timed out or failed: $e');
    }

    dynamic parsed;
    if (res.body.isNotEmpty) {
      try {
        parsed = jsonDecode(res.body);
      } catch (_) {
        parsed = null;
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return parsed;

    final err = (parsed is Map && parsed['error'] is Map) ? parsed['error'] as Map : null;
    throw ApiException(
      res.statusCode,
      (err?['code'] ?? 'HTTP_${res.statusCode}').toString(),
      (err?['message'] ?? 'Request failed (${res.statusCode})').toString(),
    );
  }
}

/// Content type from the file extension. The server only accepts images and
/// PDFs, and `MultipartFile.fromPath` will not work this out on its own.
MediaType? _mediaTypeFor(String path) {
  final ext = path.toLowerCase().split('.').last;
  switch (ext) {
    case 'jpg':
    case 'jpeg':
      return MediaType('image', 'jpeg');
    case 'png':
      return MediaType('image', 'png');
    case 'webp':
      return MediaType('image', 'webp');
    case 'heic':
      return MediaType('image', 'heic');
    case 'pdf':
      return MediaType('application', 'pdf');
    default:
      return null; // let the server decide, and say why if it refuses
  }
}

// ---------------------------------------------------------------- parsing ---
// The API mixes serialized camelCase objects with raw snake_case table rows,
// so these readers accept either spelling and cope with numbers arriving as
// strings (MySQL DECIMAL columns come back as strings through mysql2).

double? asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

bool asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '$v'.toLowerCase();
  return s == 'true' || s == '1';
}

DateTime? asDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v');
}

/// Reads the first key present, so a caller can write `pick(row, ['startDate',
/// 'start_date'])` once instead of branching everywhere.
dynamic pick(Map row, List<String> keys) {
  for (final k in keys) {
    if (row.containsKey(k) && row[k] != null) return row[k];
  }
  return null;
}

/// `HH:mm:ss` from the DB, `HH:mm` in the app.
String shortTime(dynamic v) {
  final s = '${v ?? ''}';
  final parts = s.split(':');
  if (parts.length >= 2) return '${parts[0].padLeft(2, '0')}:${parts[1]}';
  return s;
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
