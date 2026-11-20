# Leaf

Pembaca buku PDF pribadi dengan efek balik halaman 3D, sticky note yang bisa digeser, dan tab penanda halaman. Semua data tersimpan lokal di HP, tanpa internet dan tanpa iklan.

## Fitur
- Upload PDF sendiri ke rak buku
- Balik halaman seperti buku asli
- Sticky note (4 warna, bisa digeser, diedit, dihapus)
- Tab penanda untuk loncat cepat antar halaman
- Ingat halaman terakhir yang dibaca

## Build APK
Push ke branch `main`, lalu GitHub Actions akan membuat APK dan menaruhnya di halaman **Releases**.

Atau lokal:

```
flutter create --platforms=android .
flutter pub get
flutter build apk --release
```
