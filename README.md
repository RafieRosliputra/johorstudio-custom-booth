# JohorStudio.com Custom BOOTH

App photobooth untuk Mac (Apple Silicon, macOS 14+). Ditulis dalam Swift + SwiftUI, guna Core Image (GPU/Metal) untuk composite, AVFoundation untuk capture card, dan libwebp (dah di-bundle) untuk WebP.

## Build

Perlu **Xcode** (atau Command Line Tools: `xcode-select --install`).

```bash
git clone https://github.com/RafieRosliputra/johorstudio-custom-booth.git
cd johorstudio-custom-booth
./scripts/build_app.sh ~/Desktop/"20261017 ptp"
```

Script ni akan buat `build/JohorStudio Booth.app` dan copy terus ke folder event yang kau bagi.
Kali pertama build dia akan download libwebp (Swift Package), jadi kena ada internet.

Nak buka dalam Xcode: `open Package.swift`, kemudian tekan Run.
Kalau run dari Xcode, working folder = folder semasa. Untuk event, guna `.app` yang dah dibuild.

## Struktur folder event

```
Desktop/20261017 ptp/          ← working folder (letak app kat sini)
  JohorStudio Booth.app
  settings.json                 ← semua setting (auto)
  print-history.json            ← nombor COPY & WebP yang dah dibuat (auto)
  logs/2026-10-17.log
  hotfolder/                    ← JPG untuk printer (auto)
  camera/                       ← DIRECTORY: gambar dari kamera (default, boleh tukar)
    upload/                     ← WebP menunggu sync ke TrueNAS
      DONE/                     ← WebP dah ada kat TrueNAS
```

## Tab

### PRINT
- **DIRECTORY**: folder gambar kamera (JPG sahaja, folder atas sahaja).
- **SELECT OVERLAY**: PNG/WebP 2500×1667 dengan kawasan photo yang transparent. Ikon ⚙︎ sebelah nama overlay untuk ubah X/Y/W/H kawasan photo (default greenLayer 157/104/2186/1459). Nilai yang diubah kekal sampai diubah lagi.
- Preview tulis **"details not loaded"** selagi Directory/Overlay belum lengkap.
- **LATEST IMAGE NAME** (kekunci `L`): load gambar paling baru, ikut masa fail masuk folder. Butang jadi **hijau** bila ada gambar baru yang belum di-load. Preview tak berubah sendiri.
- **PREV / NEXT** (kekunci ← →): NEXT jadi kelabu bila dah kat latest, PREV jadi kelabu kat gambar pertama.
- **1–5**: popup confirm, lepas tu terus save. Kotak nombor (1–20) + **PRINT** untuk jumlah lain.
- Output untuk setiap copy: JPG 1800×1200 (4R), Q95, 300 DPI, sRGB, dalam `hotfolder/`:
  `20261017-130559-COPY-1-47.jpg` (tarikh/masa dari EXIF date taken, `47` = nombor random).
  Reprint akan sambung nombor COPY. Fail ditulis atomic supaya printer tak ambil fail separuh siap.
- Sekali untuk setiap gambar: WebP 2500×1667, quality 50, disimpan dalam `camera/upload/20261017-130559-47.webp`.

### UPLOAD ☑
- Pilih folder TrueNAS (share yang dah di-mount). Bila checkbox ditick, app test tulis/padam satu fail dulu.
  Kalau gagal: keluar popup error, checkbox jadi untick, dan masuk log. Print tetap boleh jalan.
- Masa sync: WebP yang belum ada kat TrueNAS akan di-copy (`.uploading`, lepas tu rename), kemudian dipindah ke `upload/DONE`. Yang dah ada (nama sama) terus dipindah ke DONE, tak upload dua kali.
- Sync berlaku serta-merta lepas setiap print, dan setiap 30 saat.
- Bila TrueNAS hidup balik lepas putus, header tunjuk "TrueNAS available — tick UPLOAD".

### LOG
- Ada warna INFO/OK/WARN/ERROR, dan disimpan ke `logs/`. Butang **Detach** buka log dalam window sendiri yang boleh resize. Tutup window tu, log masuk balik dalam tab.
- Masa startup app check: arm64, GPU/Metal, libwebp, folder boleh ditulis, overlay, permission kamera, capture card, bilangan monitor, dan TrueNAS.

### SCREEN (2nd screen)
- Pilih capture card dan monitor. Ada X/Y/W/H untuk kawasan live feed (default 252/67/1416/946), mirror, toggle preview dalam tab, dan berapa saat countdown.
- **Start 2nd screen**: fullscreen kat monitor kedua, cursor disorok, Esc untuk tutup.
- Live feed di-mirror, duduk bawah overlay. Bila ada gambar baru masuk DIRECTORY, gambar tu ditunjuk dengan nombor merah 5→1 dalam kotak putih (bucu kanan bawah), lepas tu kembali ke live. Kalau ada gambar lain masuk masa countdown, dia tukar ke gambar terbaru dan reset countdown.
- Kalau monitor kedua tercabut, window pindah ke skrin utama.

## Nota
- App tak di-sandbox (bukan App Store), supaya boleh baca/tulis folder event dan share TrueNAS.
- Mac takkan tidur selama app dibuka.
- Kalau app di-copy dari komputer lain dan tak jalan: `xattr -dr com.apple.quarantine "JohorStudio Booth.app"`.
