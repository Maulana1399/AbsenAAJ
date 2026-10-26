/// Minimal view of the currently authenticated user + linked employee.
library;

class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.lastLoginAt,
    this.employee,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final bool isActive;
  final DateTime? lastLoginAt;
  final EmployeeBrief? employee;

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    role: json['role'] as String? ?? '',
    isActive: json['is_active'] as bool? ?? true,
    lastLoginAt: DateTime.tryParse(json['last_login_at'] as String? ?? ''),
    employee: json['employee'] == null
        ? null
        : EmployeeBrief.fromJson(json['employee'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    'is_active': isActive,
    'last_login_at': lastLoginAt?.toIso8601String(),
    'employee': employee?.toJson(),
  };
}

class EmployeeBrief {
  const EmployeeBrief({
    required this.id,
    required this.employeeNumber,
    required this.name,
    required this.status,
  });

  final int id;
  final String employeeNumber;
  final String name;
  final String status;

  factory EmployeeBrief.fromJson(Map<String, dynamic> json) => EmployeeBrief(
    id: json['id'] as int,
    employeeNumber: json['employee_number'] as String? ?? '',
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'employee_number': employeeNumber,
    'name': name,
    'status': status,
  };
}
