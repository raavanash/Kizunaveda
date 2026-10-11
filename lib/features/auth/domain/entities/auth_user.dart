import '../../../../core/constants/app_constants.dart';

/// Represents an authenticated user in Kizuna Veda.
class AuthUser {
  final String id;
  final String email;
  final String? fullName;
  final UserRole role;
  final String? facilityLocation;

  const AuthUser({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    this.facilityLocation,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          email == other.email &&
          role == other.role;

  @override
  int get hashCode => id.hashCode ^ email.hashCode ^ role.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role.name,
      'facilityLocation': facilityLocation,
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.jaipur,
      ),
      facilityLocation: json['facilityLocation'] as String?,
    );
  }
}
