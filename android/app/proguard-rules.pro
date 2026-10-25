# Release builds shrink code with R8. Some plugins (shared_preferences via package:jni) call their
# Android code by exact name and signature from Dart, which R8 can't see. Without these rules R8
# removed or renamed that code and the app hung on the splash screen.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
# The Kotlin classes that code uses (Result, coroutines…) are looked up by name too.
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keepattributes Signature,InnerClasses,EnclosingMethod
