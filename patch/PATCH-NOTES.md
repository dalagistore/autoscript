# DLGST XRAY PANEL
## UPDATE PATCH ALL-IN-ONE FIX V1

Tanggal: 3 November 2026

### Pembaruan

- SSH Unlimited Quota dan accounting.
- Xray VMESS, VLESS, TROJAN Unlimited Quota.
- Perbaikan input kuota 0.
- SSH WebSocket Control.
- BadVPN UDP Gateway.
- Management Installer.
- Account Portal Data API.
- Account Portal Credentials Card.
- Account Portal Quota Card.
- Account Portal hasil build terbaru.

### Perbaikan Installer FIX V1

- Penggantian direktori Account Portal secara utuh.
- Pembersihan asset lama.
- Backup direktori dist secara utuh.
- Rollback direktori dist secara utuh.
- Validasi SHA256 sebelum pemasangan.
- Backup source dan runtime.
- Verifikasi hasil pemasangan.

### Keamanan

- Tidak menghapus database pelanggan.
- Tidak menghapus akun pelanggan.
- Tidak mengganti password pelanggan.
- Tidak menimpa konfigurasi pelanggan.
- Tidak menjalankan restart seluruh layanan secara otomatis.

### Instalasi

Ekstrak paket, lalu jalankan:

    bash apply-patch.sh

Jalankan sebagai root pada VPS yang sudah memiliki DLGST XRAY PANEL.
