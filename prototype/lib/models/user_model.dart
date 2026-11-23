enum UserRole {
  patient,
  driver;

  /// Value used by the backend (`patient` / `driver`).
  String get apiName => name;

  static UserRole? fromApi(String? value) {
    for (final role in UserRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

class UserModel {
  const UserModel({
    this.id = '',
    required this.name,
    this.phone = '',
    required this.role,
  });

  final String id;
  final String name;
  final String phone;
  final UserRole role;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final role = UserRole.fromApi(json['role'] as String?);
    if (role == null) {
      throw FormatException('Unsupported role: ${json['role']}');
    }
    return UserModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: role,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'role': role.apiName,
  };
}
