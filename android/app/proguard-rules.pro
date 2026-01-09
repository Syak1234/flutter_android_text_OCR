# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }

# Google Play Services
-keep class com.google.android.gms.internal.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.play.**
-dontwarn com.google.firebase.**

-allowaccessmodification
-repackageclasses ''

# Prevent obfuscation of certain types that might be used by reflection or JNI
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile,LineNumberTable

