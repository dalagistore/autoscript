# DLGST XRAY PANEL --- Patch Notes

**Dokumen:** Patch Notes\
**Tanggal:** 3 November 2026\
**Rilis:** Pembaruan kumulatif (persiapan UPDATE PATCH ALL-IN-ONE)

------------------------------------------------------------------------

## Ringkasan

Dokumen ini merangkum perubahan yang sudah dikerjakan dan diverifikasi
dalam percakapan proyek DLGST XRAY PANEL. Dokumen ini juga menjadi
daftar cakupan untuk paket **UPDATE PATCH ALL-IN-ONE**.

> **Status penting:** Arsip FULL INSTALLER
> `DLGST-XRAY-PANEL-FULL-INSTALLER-20261103.tar.gz` sudah berhasil
> dibuat dan lolos pemeriksaan integritas arsip. Paket **UPDATE PATCH
> ALL-IN-ONE belum dibuat atau diuji**. Karena itu, daftar cakupan di
> bawah tidak boleh dianggap sebagai bukti bahwa satu paket patch
> gabungan sudah tersedia.

## 1. Perbaikan Unlimited Quota

### Perilaku kuota

-   Nilai kuota `0` dimaksudkan sebagai **unlimited**.
-   Trafik tetap dicatat meskipun akun menggunakan kuota unlimited.
-   Akun unlimited tidak boleh diblokir hanya karena flag kuota lama
    atau status quota-exhausted yang sudah tidak relevan.
-   Batas masa aktif, IP limit, speed limit, dan manual lock tetap
    berlaku.

### Protokol yang telah diuji

Pengujian akun unlimited yang dilaporkan berhasil:

  Protokol                    Trafik tercatat Status quota
  --------------- --------------------------- -----------------
  SSH SSL/TLS               173,302,773 bytes Tidak exhausted
  SSH WebSocket     16,461,285 bytes tambahan Tidak exhausted
  VMESS                       1,570,202 bytes Tidak exhausted
  VLESS                         615,408 bytes Tidak exhausted
  TROJAN                      5,254,679 bytes Tidak exhausted

Catatan: angka di atas adalah hasil pengujian yang dilaporkan pada sesi
pengerjaan, bukan hasil pengujian ulang oleh dokumen ini.

## 2. Perbaikan SSH

-   Penanganan unlimited quota pada SSH diperbaiki agar nilai kuota `0`
    tidak menyebabkan pemblokiran kuota.
-   Pencatatan trafik SSH SSL/TLS dan WebSocket telah diuji.
-   Prompt pembuatan akun diperbaiki agar input `0` dapat dipakai
    sebagai nilai kuota unlimited dan tidak keliru dianggap sebagai
    pilihan kembali.
-   Perbaikan helper pilihan Ya/Tidak diselaraskan.

## 3. Perbaikan Xray

-   Penanganan unlimited quota untuk VMESS, VLESS, dan TROJAN telah
    diuji.
-   Trafik tetap tercatat pada akun unlimited.
-   Input kuota `0` pada alur pembuatan akun diperbaiki agar diterima
    sebagai unlimited.

## 4. WireGuard dan Shadowsocks

Komponen berikut ditemukan di source FULL INSTALLER:

-   Script pengelolaan pengguna WireGuard.
-   Script pengelolaan pengguna Shadowsocks.
-   Installer WireGuard/Shadowsocks.
-   Template systemd service dan timer expiry WireGuard.

Keberadaan file di arsip telah diperiksa. Namun, dokumen ini **tidak
menyatakan seluruh alur instalasi, pembuatan akun, perpanjangan,
penghapusan, dan koneksi WireGuard/Shadowsocks sudah lulus uji VPS
kosong**.

## 5. Account Portal --- SSH Credentials

Perubahan tampilan portal yang sudah diterapkan pada source dan hasil
build:

-   Kartu Kredensial dipindahkan agar menggunakan lebar penuh
    (full-width).
-   Tata letak username dan password diperbaiki.
-   Nilai username dan password mendukung pemenggalan teks panjang.
-   Tombol salin (Copy) tetap tersedia.
-   Tombol tampil/sembunyikan password (Show/Hide) tetap tersedia.
-   Tata letak disesuaikan agar lebih nyaman di desktop dan perangkat
    mobile.

Build portal berhasil setelah dependensi npm dipasang menggunakan
lockfile. Hasil `dist` kemudian disalin ke runtime
`/opt/account-portal/web/dist` dan tampilan telah dikonfirmasi berhasil
oleh pengguna.

## 6. FULL INSTALLER

Arsip yang berhasil dibuat:

``` text
/root/DLGST-XRAY-PANEL-FULL-INSTALLER-20261103.tar.gz
```

Rincian hasil pemeriksaan:

  Pemeriksaan                        Hasil
  ---------------------------------- -----------
  Ukuran arsip                       23 MB
  Jumlah entri file                  447
  `setup.sh`                         Ditemukan
  `run.sh`                           Ditemukan
  `manage.sh`                        Ditemukan
  Management installer               Ditemukan
  Script pengguna WireGuard          Ditemukan
  Script pengguna Shadowsocks        Ditemukan
  Template service/timer WireGuard   Ditemukan
  Account Portal `dist/index.html`   Ditemukan
  Integritas gzip                    Valid

**SHA256:**

``` text
ad0bd07024c4c239fa8385b072cede4924727d2b734fa5e443f4e83e8e2b4600
```

Pemeriksaan arsip membuktikan arsip dapat dibaca dan file yang dicari
tersedia. Pemeriksaan tersebut belum membuktikan instalasi bersih
berhasil pada VPS Debian 12 baru.

## 7. Cakupan target UPDATE PATCH ALL-IN-ONE

Paket patch gabungan direncanakan mencakup:

1.  Perbaikan unlimited quota Xray (VMESS, VLESS, TROJAN).
2.  Perbaikan unlimited quota dan accounting SSH.
3.  Perbaikan prompt kuota `0`.
4.  Integrasi/perbaikan komponen WireGuard.
5.  Integrasi/perbaikan komponen Shadowsocks.
6.  Sinkronisasi management script dan installer terkait.
7.  Account Portal dengan tampilan SSH Credentials terbaru.

**Status paket:** belum dibangun, belum diverifikasi kelengkapan file
patch-nya, dan belum diuji sebagai satu paket update.

## 8. Ketentuan keamanan update

Paket UPDATE PATCH ALL-IN-ONE harus dirancang untuk:

-   Membuat backup file target sebelum perubahan.
-   Tidak menghapus akun pelanggan.
-   Tidak mengubah password pelanggan.
-   Tidak menghapus database atau metadata pelanggan.
-   Tidak mereset konfigurasi layanan yang sudah berjalan.
-   Tidak menimpa file konfigurasi runtime pelanggan dengan konfigurasi
    contoh.
-   Memeriksa file dan checksum sebelum pemasangan.
-   Menyediakan rollback dari backup jika pemasangan gagal.
-   Menampilkan ringkasan file yang diubah.

## 9. Pengujian sebelum rilis

Sebelum patch gabungan dinyatakan siap produksi, lakukan pengujian pada
VPS Debian 12 uji coba:

-   Instalasi/update patch tanpa menghapus akun lama.
-   Login dan koneksi SSH, termasuk WebSocket dan SSL/TLS.
-   Koneksi VMESS, VLESS, dan TROJAN.
-   Koneksi WireGuard dan Shadowsocks.
-   Trafik akun unlimited tetap tercatat dan tidak terkena blokir kuota.
-   Expiry, IP limit, speed limit, dan manual lock tetap bekerja.
-   Create, renew, delete, dan pemeriksaan akun.
-   Account Portal menampilkan SSH Credentials dengan benar.
-   Rollback dapat memulihkan file sebelumnya.

------------------------------------------------------------------------

**Catatan rilis:** Gunakan FULL INSTALLER untuk pengujian instalasi VPS
baru setelah pengujian bersih dilakukan. Jangan menganggap dokumen ini
sebagai instruksi menjalankan patch; paket UPDATE PATCH ALL-IN-ONE masih
harus dirakit dan diuji secara terpisah.
