import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/constants/app_constants.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

@freezed
class UserProfile with _$UserProfile {
  const factory UserProfile({
    required String id,
    String? email,
    String? displayName,
    @Default(false) bool isPremium,
    @Default(true) bool notificationsEnabled,
    @Default(9) int notificationHour,
    @Default(0) int notificationMinute,
    @Default(3) int notifyDaysBefore,
    @Default('ru') String locale,
    @Default('system') String themeMode,
    DateTime? createdAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);
}

extension UserProfileX on UserProfile {
  int get productLimit {
    if (!AppConstants.billingEnabled) return AppConstants.maxPremiumProducts;
    return isPremium
        ? AppConstants.maxPremiumProducts
        : AppConstants.maxFreeProducts;
  }
}
