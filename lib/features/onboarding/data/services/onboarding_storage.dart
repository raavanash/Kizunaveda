import 'dart:convert';
import 'dart:io';

/// User-scoped persistence service to track onboarding completion status.
/// Prevents repeatedly displaying introductory walkthroughs while allowing
/// users to restart the tour on demand.
class OnboardingStorage {
  static OnboardingStorage instance = OnboardingStorage();

  final Set<String> _completedUsers = <String>{};
  final File? storageFile;

  OnboardingStorage({this.storageFile});

  /// Check if the specified user has completed or skipped the onboarding guide.
  Future<bool> isCompleted(String userId) async {
    if (userId.isEmpty) return false;
    if (_completedUsers.contains(userId)) return true;

    try {
      if (storageFile != null && await storageFile!.exists()) {
        final content = await storageFile!.readAsString();
        if (content.isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          _completedUsers.addAll(list.cast<String>());
          return _completedUsers.contains(userId);
        }
      }
    } catch (_) {}

    return _completedUsers.contains(userId);
  }

  /// Mark onboarding as completed for the specified user.
  Future<void> markCompleted(String userId) async {
    if (userId.isEmpty) return;
    _completedUsers.add(userId);

    try {
      if (storageFile != null) {
        final jsonString = jsonEncode(_completedUsers.toList());
        await storageFile!.writeAsString(jsonString);
      }
    } catch (_) {}
  }

  /// Reset onboarding completion status for the specified user (e.g. to restart tour).
  Future<void> reset(String userId) async {
    _completedUsers.remove(userId);

    try {
      if (storageFile != null && await storageFile!.exists()) {
        final jsonString = jsonEncode(_completedUsers.toList());
        await storageFile!.writeAsString(jsonString);
      }
    } catch (_) {}
  }

  /// Clear all onboarding records (primarily for testing).
  void clearMemory() {
    _completedUsers.clear();
  }
}
