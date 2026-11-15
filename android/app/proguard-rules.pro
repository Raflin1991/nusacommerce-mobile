# NusaCommerce POS — Android R8 / ProGuard Keep Rules

# Keep Flutter Engine & Plugin Channels
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

# Keep Bluetooth Thermal Printer Driver (print_bluetooth_thermal)
-keep class app.web.groons.print_bluetooth_thermal.** { *; }
-dontwarn app.web.groons.print_bluetooth_thermal.**

# Keep SQLite Engine (sqflite)
-keep class com.tekartik.sqflite.** { *; }
-dontwarn com.tekartik.sqflite.**

# Keep Permission Handler
-keep class com.baseflow.permissionhandler.** { *; }
