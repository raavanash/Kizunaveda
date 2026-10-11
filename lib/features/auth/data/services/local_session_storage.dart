import 'dart:convert';
import 'dart:io';
import '../../domain/entities/auth_session.dart';
import '../../domain/services/session_storage.dart';

/// In-memory and local file session storage for Kizuna Veda session persistence.
/// Ready to swap with flutter_secure_storage when native keyrings are attached.
class LocalSessionStorage implements ISessionStorage {
  AuthSession? _cachedSession;
  final File? storageFile;

  LocalSessionStorage({this.storageFile});

  @override
  Future<AuthSession?> readSession() async {
    if (_cachedSession != null) return _cachedSession;

    try {
      if (storageFile != null && await storageFile!.exists()) {
        final content = await storageFile!.readAsString();
        if (content.isNotEmpty) {
          final jsonMap = jsonDecode(content) as Map<String, dynamic>;
          _cachedSession = AuthSession.fromJson(jsonMap);
          return _cachedSession;
        }
      }
    } catch (_) {
      // Clear corrupt session file if reading fails
      await clearSession();
    }
    return null;
  }

  @override
  Future<void> writeSession(AuthSession session) async {
    _cachedSession = session;
    try {
      if (storageFile != null) {
        final jsonString = jsonEncode(session.toJson());
        await storageFile!.writeAsString(jsonString);
      }
    } catch (_) {}
  }

  @override
  Future<void> clearSession() async {
    _cachedSession = null;
    try {
      if (storageFile != null && await storageFile!.exists()) {
        await storageFile!.delete();
      }
    } catch (_) {}
  }
}
