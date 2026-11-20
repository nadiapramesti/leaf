# Leaf

Pembaca buku PDF pribadi, simpel ala Google Books. Upload PDF sendiri, baca dengan efek balik halaman, tempel sticky note, pasang tab penanda, coret pakai stylus, lalu ubah tulisan tangan jadi teks dengan gaya huruf pilihan. Semua data tersimpan di HP.

## Fitur
- Rak buku dengan sampul otomatis dari halaman pertama PDF
- Balik halaman seperti buku asli, slider untuk loncat halaman
- Sticky note: 4 warna, 4 gaya huruf, bisa digeser
- Tab penanda halaman
- Mode Tulis & Stabilo untuk stylus (sentuhan telapak diabaikan, tombol hapus stylus = penghapus)
- Ubah tulisan tangan jadi teks (Google ML Kit, offline setelah model diunduh)
- Mode terang & gelap, splash animasi

## Build APK
Push ke `main`, GitHub Actions membuat APK dan menaruhnya di **Releases**.

Lokal:
```
flutter create --platforms=android .
flutter pub get
flutter analyze
flutter build apk --release
```

Dibuat dengan bantuan AI (Claude).
