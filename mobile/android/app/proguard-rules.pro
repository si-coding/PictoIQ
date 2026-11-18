# Release builds shrink and rename Android code (R8). The ML Kit plugins find
# their classes by name at run time, so they must be left as they are, or the
# face and object checks fail in release builds ("MissingPluginException",
# "InputImageConverterError").
-keep class com.google_mlkit_** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
