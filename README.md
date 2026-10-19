# johorstudio-custom-photobooth

App photobooth untuk Mac (Apple Silicon, macOS 14+). Ditulis dalam Swift + SwiftUI, guna Core Image (GPU/Metal) untuk composite, AVFoundation untuk capture card, dan libwebp (dah di-bundle) untuk WebP.

## Cara build (step by step)

Semua ni buat sekali je. Lepas tu, setiap kali ada update, ulang **Langkah 3 & 4** sahaja.

**Langkah 1: buka Terminal**
Tekan `⌘ + Space`, taip `Terminal`, tekan Enter.

**Langkah 2: pasang alat Apple untuk compile (sekali je)**
Dalam Terminal, taip arahan ni dan tekan Enter:
```bash
xcode-select --install
```
Akan keluar satu popup. Tekan **Install** dan tunggu sampai siap (5–15 minit).
Kalau keluar mesej *"already installed"*, maksudnya dah ada, terus ke langkah seterusnya.

**Langkah 3: download kod**
```bash
cd ~/Desktop
git clone https://github.com/RafieRosliputra/johorstudio-custom-booth.git
```
Ni akan buat folder `johorstudio-custom-booth` kat Desktop.
(Kalau folder tu dah ada dari sebelum ni, untuk ambil update: `cd ~/Desktop/johorstudio-custom-booth && git pull`)

**Langkah 4: build**
```bash
cd ~/Desktop/johorstudio-custom-booth
./scripts/build_app.sh
```
Atau dalam Finder, double-click fail **`build.command`** dalam folder tu.
Kali pertama ambil masa beberapa minit, sebab dia download libwebp (perlu internet).
Bila dah siap, Finder akan buka folder `build` yang ada **`johorstudio-custom-photobooth.app`**.

**Langkah 5: guna untuk event**
1. Buat satu folder untuk event, contohnya `Desktop/MyEvent`.
2. Copy `johorstudio-custom-photobooth.app` masuk dalam folder tu.
3. Double-click app tu. Folder `camera` dan `logs` akan dibuat sendiri dalam folder event tu.
4. Tekan **HOTFOLDER** dan pilih folder hotfolder printer (boleh di mana-mana).

Kalau ada error masa build, copy semua tulisan dalam Terminal dan hantar kat Claude.

## Struktur folder event

```
Desktop/MyEvent/               ← folder event (letak app kat sini)
  johorstudio-custom-photobooth.app
  settings.json                 ← semua setting (auto)
  print-history.json            ← nombor COPY & WebP yang dah dibuat (auto)
  logs/2026-10-17.log
  camera/                       ← DIRECTORY: gambar dari kamera (default, boleh tukar)
    upload/                     ← WebP menunggu sync ke TrueNAS
      DONE/                     ← WebP dah ada kat TrueNAS
```

## Tab

### PRINT
- **DIRECTORY**: folder gambar kamera (JPG sahaja, folder atas sahaja).
- **HOTFOLDER**: folder hotfolder printer, boleh di mana-mana (contohnya folder software printer). Disimpan dalam settings.
- **SELECT OVERLAY**: PNG/WebP 2500×1667 dengan kawasan photo yang transparent. Ikon ⚙︎ sebelah nama overlay untuk ubah X/Y/W/H kawasan photo (default greenLayer 157/104/2186/1459). Nilai yang diubah kekal sampai diubah lagi.
- Preview tulis **"details not loaded"** selagi Directory, Hotfolder atau Overlay belum lengkap.
- **LATEST IMAGE NAME** (kekunci `L`): load gambar paling baru, ikut masa fail masuk folder. Butang jadi **hijau** bila ada gambar baru yang belum di-load. Preview tak berubah sendiri.
- **PREV / NEXT** (kekunci ← →): NEXT jadi kelabu bila dah kat latest, PREV jadi kelabu kat gambar pertama.
- **1–5**: popup confirm, lepas tu terus save. Kotak nombor (1–20) + **PRINT** untuk jumlah lain.
- **UPLOAD** (bawah PRINT): buat WebP sahaja dan hantar ke TrueNAS, tiada JPG ke hotfolder. Kalau WebP gambar tu dah pernah dibuat, dia tak buat lagi.
- Output untuk setiap copy: JPG 1800×1200 (4R), Q95, 300 DPI, sRGB, dalam folder **HOTFOLDER** yang dipilih:
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
- Pilih capture card dan monitor. Ada X/Y/W/H untuk kawasan live feed (default 252/67/1416/946), mirror live feed, mirror overlay (2nd screen sahaja, print tak terjejas), toggle preview dalam tab, dan berapa saat countdown.
- **Start 2nd screen**: fullscreen kat monitor kedua, cursor disorok, Esc untuk tutup.
- Live feed di-mirror, duduk bawah overlay. Bila ada gambar baru masuk DIRECTORY, gambar tu ditunjuk dengan nombor merah 5→1 dalam kotak putih (bucu kanan bawah), lepas tu kembali ke live. Kalau ada gambar lain masuk masa countdown, dia tukar ke gambar terbaru dan reset countdown.
- Kalau monitor kedua tercabut, window pindah ke skrin utama.

## Nota
- App tak di-sandbox (bukan App Store), supaya boleh baca/tulis folder event dan share TrueNAS.
- Mac takkan tidur selama app dibuka.
- Kalau app di-copy dari komputer lain dan tak jalan: `xattr -dr com.apple.quarantine "johorstudio-custom-photobooth.app"`.
