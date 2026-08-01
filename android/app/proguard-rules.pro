# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }

# ML Kit: динамически загружаемые модели
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.internal.mlkit_** { *; }

# flutter_local_notifications (Gson-сериализация)
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-dontwarn com.dexterous.**

# Isar
-keep class dev.isar.** { *; }

# speech_to_text
-keep class android.speech.** { *; }

# Java 8+ desugaring
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
