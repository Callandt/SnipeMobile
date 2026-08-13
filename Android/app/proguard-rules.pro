# SnipeMobile ProGuard / R8 rules
# Kept ready for when minify is re-enabled after on-device validation.

-keepattributes SourceFile,LineNumberTable,*Annotation*,InnerClasses,EnclosingMethod,Signature,Exception
-renamesourcefileattribute SourceFile

# Kotlin Serialization
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class com.callandt.snipemobile.**$$serializer { *; }
-keepclassmembers class com.callandt.snipemobile.** {
    *** Companion;
}
-keepclasseswithmembers class com.callandt.snipemobile.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep @kotlinx.serialization.Serializable class * { *; }

# App entry points + enums used at runtime
-keep class com.callandt.snipemobile.SnipeMobileApp { *; }
-keep class com.callandt.snipemobile.MainActivity { *; }
-keep class com.callandt.snipemobile.data.model.** { *; }
-keep class com.callandt.snipemobile.data.prefs.** { *; }
-keep class com.callandt.snipemobile.data.secure.** { *; }
-keep class com.callandt.snipemobile.widget.** { *; }
-keep class com.callandt.snipemobile.notifications.** { *; }
-keepclassmembers enum * { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# CameraX / ML Kit
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}
