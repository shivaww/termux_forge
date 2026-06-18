# TermuxForge ProGuard Rules
# Flutter-specific rules are included automatically.

# Keep Flutter plugin registrants
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep FileProvider
-keep class androidx.core.content.FileProvider { *; }

# Keep annotation interfaces
-keepattributes *Annotation*

# Suppress warnings for common dependencies
-dontwarn javax.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Ignore missing Play Core classes for Flutter Deferred Components
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
