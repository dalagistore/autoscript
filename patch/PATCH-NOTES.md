# DLGST XRAY PANEL — UPDATE PATCH ALL-IN-ONE
Tanggal: 3 November 2026

## Cakupan
- SSH quota accounting dan pengelolaan akun.
- Xray VMESS, VLESS, TROJAN quota accounting dan pengelolaan akun.
- SSH WebSocket control.
- BadVPN UDP Gateway launcher.
- Management installer.
- Account Portal data API.
- Account Portal: Credentials Card, Quota Card, layout, dan hasil build terbaru.

## Instalasi
Ekstrak arsip lalu jalankan:
bash apply-patch.sh

## Keamanan
Installer membuat backup file target sebelum pemasangan.
Database dan data akun pelanggan tidak termasuk payload.
WireGuard dan Shadowsocks tidak ditimpa oleh patch ini karena file runtime
yang diperiksa sebelumnya sudah sama dengan source.
