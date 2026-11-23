# R8 dropped WorkDatabase's constructor and the process died on launch.

-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

-keep class androidx.work.impl.WorkDatabase { <init>(...); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.impl.WorkDatabase_Impl$* { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}

# Loaded by name from MlKitInitProvider.
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar,
            com.google.mlkit.vision.common.internal.VisionCommonRegistrar,
            com.google.mlkit.vision.barcode.internal.BarcodeRegistrar {
    <init>();
    *** getComponents(...);
}

-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-keep class kotlinx.coroutines.android.AndroidExceptionPreHandler { *; }
-keep class kotlinx.coroutines.internal.MainDispatcherFactory { *; }

-keep class com.callandt.snipemobile.widget.glance.*Receiver { <init>(); }
-keep class com.callandt.snipemobile.widget.glance.*GlanceWidget { <init>(); }

-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn com.google.mlkit.**
