enum UserRole {
  passenger('PASSENGER'),
  driver('DRIVER'),
  admin('ADMIN');

  const UserRole(this.code);
  final String code;

  static UserRole fromCode(String? code) =>
      values.firstWhere((r) => r.code == code, orElse: () => UserRole.passenger);
}

enum DriverStatus {
  pending('PENDING'),
  approved('APPROVED'),
  rejected('REJECTED'),
  suspended('SUSPENDED');

  const DriverStatus(this.code);
  final String code;

  static DriverStatus fromCode(String? code) =>
      values.firstWhere((s) => s.code == code, orElse: () => DriverStatus.pending);
}

class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.onboarded,
    this.fullName,
    this.phone,
    this.avatarUrl,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.isSuspended = false,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        role: UserRole.fromCode(j['role'] as String?),
        onboarded: j['onboarded'] as bool? ?? false,
        fullName: j['full_name'] as String?,
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        emergencyContactName: j['emergency_contact_name'] as String?,
        emergencyContactPhone: j['emergency_contact_phone'] as String?,
        isSuspended: j['account_status'] == 'SUSPENDED',
      );

  final String id;
  final UserRole role;
  final bool onboarded;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final bool isSuspended;

  String get firstName => (fullName ?? '').trim().split(' ').first;
}

class DriverInfo {
  const DriverInfo({required this.status, required this.isOnline, this.rejectionReason});

  factory DriverInfo.fromJson(Map<String, dynamic> j) => DriverInfo(
        status: DriverStatus.fromCode(j['status'] as String?),
        isOnline: j['is_online'] as bool? ?? false,
        rejectionReason: j['rejection_reason'] as String?,
      );

  final DriverStatus status;
  final bool isOnline;
  final String? rejectionReason;
}

abstract interface class ProfileRepository {
  Future<Profile?> fetchMine();

  /// Finishes onboarding. Role is validated server-side: only PASSENGER or
  /// DRIVER can be chosen, and drivers start as PENDING.
  Future<void> completeProfile({
    required String fullName,
    required UserRole role,
    String? cityId,
  });

  Future<void> updateEmergencyContact({String? name, String? phone});

  Future<DriverInfo?> fetchMyDriverInfo();
}
