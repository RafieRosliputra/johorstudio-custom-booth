# Pasang dari macOS 27 yang baru (fresh install)

Panduan ni untuk Mac Apple Silicon (M1/M2/M3/M4) yang baru siap install macOS 27.
Ikut dari atas ke bawah. Setiap langkah buat sekali je, kecuali bahagian **Update**.

---

## 1. Buka Terminal

Tekan `⌘ + Space`, taip `Terminal`, kemudian tekan Enter.
Semua arahan dalam kotak hitam kat bawah ni ditaip (atau di-paste) dalam Terminal, lepas tu tekan Enter.

## 2. Pasang Command Line Tools (alat compile Apple)

```bash
xcode-select --install
```

- Akan keluar popup. Tekan **Install**, kemudian **Agree**, dan tunggu sampai siap (5–15 minit).
- Kalau keluar mesej `already installed`, maksudnya dah ada. Terus ke langkah 3.
- **Xcode penuh tak perlu.** Command Line Tools dah cukup.

Lepas siap, check (kedua-dua arahan kena keluar nombor versi):
```bash
swift --version
git --version
```

## 3. Download kod dari GitHub

```bash
cd ~/Desktop
git clone https://github.com/RafieRosliputra/johorstudio-custom-booth.git
```

Ni akan buat folder `johorstudio-custom-booth` kat Desktop.

> Kalau GitHub tanya username/password: repo ni private, jadi kena login dulu.
> Cara paling senang, pasang GitHub CLI (`brew install gh`, lepas tu `gh auth login`), atau guna GitHub Desktop.
> Cara lain: buat *Personal Access Token* kat github.com › Settings › Developer settings, dan guna token tu sebagai password.

## 4. Build app

```bash
cd ~/Desktop/johorstudio-custom-booth
./scripts/build_app.sh
```

Atau dalam Finder, double-click **`build.command`** dalam folder tu.

- Build pertama ambil masa 2–5 minit, sebab dia download dan compile libwebp. **Kena ada internet.**
- Bila siap, Finder akan buka folder `build` yang ada **`johorstudio-custom-photobooth.app`**.
- Warning kuning (`warning:`) boleh abaikan. Yang perlu dirisaukan cuma `error:`.

## 5. Sediakan folder event

1. Buat satu folder untuk event, contohnya `~/Desktop/MyEvent`.
2. Copy `johorstudio-custom-photobooth.app` dari folder `build` masuk ke folder event tu.
3. Double-click app tu. Folder `camera` dan `logs` serta fail `settings.json` akan dibuat sendiri dalam folder event tu.

> Setiap event guna folder sendiri, dengan satu copy app dalam setiap folder.
> Setting (overlay, hotfolder, TrueNAS dan lain-lain) disimpan dalam folder event tu.

## 6. Benarkan permission (kali pertama buka app)

macOS akan tanya beberapa permission. Tekan **Allow** untuk semua:

| Popup | Kenapa |
|---|---|
| Camera | Untuk live feed dari capture card (tab SCREEN) |
| Desktop / Documents folder | Untuk baca gambar dan simpan fail print |
| Network volumes | Untuk upload ke TrueNAS |

Kalau tertekan **Don't Allow**: pergi ke **System Settings › Privacy & Security**, cari kategori tu (contohnya Camera), dan hidupkan `johorstudio-custom-photobooth`.

## 7. Printer

1. **System Settings › Printers & Scanners**, tambah printer.
2. Set printer tu sebagai **Default printer**. Butang **PURGE PRINT QUEUE** guna printer default ni.
3. Pasang software hotfolder printer (contohnya DNP Hot Folder) dan set folder hotfolder dia.
4. Dalam app, tekan **HOTFOLDER** dan pilih folder hotfolder yang sama.

## 8. TrueNAS (untuk upload)

1. Dalam Finder, tekan `⌘ + K`, masukkan `smb://ALAMAT-TRUENAS/NAMA-SHARE`, kemudian Connect.
2. Supaya share tu mount sendiri setiap kali login: **System Settings › General › Login Items** › tambah share tu (drag dari Finder).
3. Dalam app: buka tab **UPLOAD**, tekan **Choose folder…**, pilih folder dalam `/Volumes/NAMA-SHARE/...`, kemudian tick checkbox **UPLOAD**.

## 9. Capture card & monitor kedua

1. Pasang capture card HDMI (contohnya Elgato Cam Link) dan sambung ke output HDMI kamera.
2. Sambung monitor kedua. Dalam **System Settings › Displays**, pilih **Extend** (jangan Mirror).
3. Dalam app, buka tab **SCREEN**:
   - Pilih capture card dan monitor.
   - Tekan **Start 2nd screen**.

## 10. Setting Mac untuk event (disyorkan)

- **System Settings › Lock Screen**: set *Turn display off* kepada **Never** semasa event. App sendiri dah halang Mac tidur selagi app dibuka.
- **System Settings › Notifications**: hidupkan *Do Not Disturb* semasa event.
- **System Settings › General › Software Update**: tutup auto update supaya Mac tak restart tengah event.

---

## Update (bila ada versi baru kat GitHub)

```bash
cd ~/Desktop/johorstudio-custom-booth
git pull
./scripts/build_app.sh
```

Lepas tu copy `build/johorstudio-custom-photobooth.app` yang baru ke folder event dan ganti yang lama.
Setting event tak hilang, sebab ia disimpan dalam `settings.json` dalam folder event, bukan dalam app.

---

## Masalah biasa

| Masalah | Penyelesaian |
|---|---|
| `xcrun: error: invalid active developer path` (selalunya lepas update macOS) | Jalankan `xcode-select --install` semula |
| `swift: command not found` | Langkah 2 belum siap. Jalankan `xcode-select --install` |
| `LIBCLANG FATAL ERROR: IO failure on output stream` / `Abort trap: 6` | Berlaku bila build atas disk luar / NAS. Script baru dah compile dalam `~/Library/Caches`. Jalankan `git pull` dan build semula |
| Build gagal dengan `error:` | Copy baris yang ada `error:` dan hantar ke Claude |
| App tak boleh dibuka ("damaged" / "unidentified developer") | `xattr -dr com.apple.quarantine ~/Desktop/MyEvent/johorstudio-custom-photobooth.app`, atau klik kanan app › **Open** |
| Kamera / capture card tak keluar | Permission Camera (langkah 6). Cabut dan pasang semula capture card, kemudian tekan **Refresh devices** |
| Permission kamera ditanya lagi lepas update | Normal untuk app yang dibuild sendiri. Tekan **Allow** semula |
| UPLOAD untick sendiri | TrueNAS tak connect. Mount semula share tu (langkah 8) dan tick semula |
| Icon lama masih keluar | Padam app lama, copy yang baru. Kalau masih sama, restart Dock: `killall Dock` |
| Log ada `ERROR` masa startup | Buka tab **LOG**. Setiap error ada penerangan apa yang tak ada atau tak boleh diakses |
