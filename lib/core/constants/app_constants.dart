class AppConstants {
  /// Включить только вместе с рабочей интеграцией App Store / Google Play.
  static const bool billingEnabled = false;
  static const int maxFreeProducts = 20;
  static const int maxPremiumProducts = 9999;
  static const String expiryChannelId = 'expiry_channel';
  static const String expiryChannelName = 'Сроки годности';
  static const String expiryCheckTaskName = 'checkExpiringProducts';
  static const int criticalThresholdDays = 1;
  static const int expiringSoonThresholdDays = 3;
  static const String zoneFridge = 'fridge';
  static const String zoneFreezer = 'freezer';
  static const String zonePantry = 'pantry';
  static const String addManual = 'manual';
  static const String addOcr = 'ocr';
  static const String addBarcode = 'barcode';
  static const String addVoice = 'voice';
  static const String statusFresh = 'fresh';
  static const String statusExpiringSoon = 'expiring_soon';
  static const String statusCritical = 'critical';
  static const String statusExpired = 'expired';
  static const String statusConsumed = 'consumed';
  static const String statusWasted = 'wasted';
  static const String receiptsBucket = 'receipts';
}
