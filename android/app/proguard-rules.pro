# Keep Firestore data model classes (fields read/written by reflection).
-keep class com.retainic.app.data.** { *; }
-keepclassmembers class com.retainic.app.data.** {
    <init>();
    <fields>;
}
