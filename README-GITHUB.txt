DLGST XRAY PANEL — NO VPS IP LICENSE GUARD PATCH

Tujuan: menghapus VPS IP License Guard dari alur instalasi pertama, Manage Panel,
Account Portal, dan integrasi Telegram. WARP+ License Key dan Xray Customer IP Limit
tetap dipertahankan.

PENTING: file paling kritis untuk prompt aktivasi instalasi pertama adalah run.sh.
Pada source lama, run.sh memanggil run_license_preflight dan menampilkan langkah
"Validasi lisensi IP VPS". Versi run.sh dalam ZIP ini sudah menghapus preflight tersebut.

CARA UPLOAD KE GITHUB
1. Ekstrak ZIP ke komputer.
2. Salin seluruh isi folder source ke root repository GitHub (bukan membuat folder baru).
3. Replace file yang ada sesuai struktur folder.
4. Hapus file yang tercantum di DELETE-FILES.txt dari repository.
5. Commit ke branch main.

FILE MODIFIED: 25
FILE DELETED: 7

Sesudah upload, cek raw run.sh pada branch main dan pastikan tidak ada:
- run_license_preflight
- Validasi lisensi IP VPS
- autoscript-license-check

Jangan menghapus WARP+ License Key atau Xray Customer IP Limit.
