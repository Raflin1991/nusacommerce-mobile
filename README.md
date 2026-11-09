# NusaCommerce Mobile (NusaPOS & Owner Super-App) — v2.0.0

Aplikasi smartphone enterprise (Android, iOS & Handheld POS Sunmi/iMin) berbasis **Flutter 3.24+ (Dart 3.5+)** dengan **Clean Architecture**, **BLoC State Management**, dan **Offline-First Synchronization** yang terintegrasi penuh dengan **NusaCommerce Cloud Multi-Tenant REST API v1**.

---

## Cara Menjalankan Proyek Flutter

1. Buka terminal pada folder `NUSACOMMERCE MOBILE`:
   ```bash
   cd "d:/laragon/www/Nusacommerce/NUSACOMMERCE MOBILE"
   ```
2. Jika folder platform native (`android/`, `ios/`) belum di-generate penuh oleh SDK lokal Anda, jalankan:
   ```bash
   flutter create . --project-name nusacommerce_mobile --org id.nusacommerce
   ```
   *(Perintah ini hanya melengkapi file Gradle/Runner bawaan tanpa menimpa kode di dalam `lib/` dan `pubspec.yaml`).*
3. Unduh seluruh paket dependensi dan jalankan aplikasi:
   ```bash
   flutter pub get
   flutter run
   ```

---

## Konfigurasi Koneksi ke Backend Laravel NusaCommerce Cloud

Secara bawaan, aplikasi mengarah ke `http://10.0.2.2:8000/api/v1` (Android Emulator) atau dapat diubah langsung melalui ikon **Server Cloud** di pojok kanan atas layar **Masuk Akun Toko (`/login`)**:
- **Android Emulator**: `http://10.0.2.2:8000/api/v1`
- **Smartphone Fisik (Wi-Fi LAN yang sama)**: `http://<IP-LAPTOP-ANDA>:8000/api/v1`
- **Domain Cloud Produksi**: `https://app.nusacommerce.id/api/v1`
