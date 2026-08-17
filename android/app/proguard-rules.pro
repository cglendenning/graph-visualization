# Flutter's engine looks these up reflectively; R8 cannot see the references.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
