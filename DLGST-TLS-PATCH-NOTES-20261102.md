# DLGST XRAY PANEL — TLS/ACME hardening patch

## Changes
- Reuse a valid installed certificate when the domain and private key match.
- Recover a previously issued valid certificate from the local acme.sh home (`~/.acme.sh/<domain>[_ecc]/`) when the installed `/opt/cert` files are missing.
- Remove forced issuance (`--force`) from initial setup to avoid unnecessary re-issuance and rate-limit consumption.
- Capture ACME output and classify rate-limit (HTTP 429), connectivity/port, DNS/authorization, and generic failures.
- Parse Let's Encrypt `retry after ... UTC` and show the corresponding Asia/Jakarta time when available.
- Add explicit staging mode: set `DLGST_ACME_STAGING=1` in the environment before running setup. Staging certificates are not browser-trusted and are for installer validation only.
- Keep the primary domain installer and backup domain installer in sync.

## Important behavior
- Production remains the default (`ACME_DEFAULT_CA`, normally `letsencrypt`). Staging is never enabled automatically.
- A rate limit cannot be bypassed by installer changes. Wait until the CA-provided retry time, or use staging only for testing.
- This patch does not alter DNS records, firewall rules, or customer account data.

## Validation performed
- `bash -n` on `opt/setup/install/domain.sh` and `opt/setup/install/backup_domain.sh`.
- Static checks confirm issue commands no longer use `--force` and both domain modules use the shared diagnostic wrapper.
- A real Let's Encrypt issuance and fresh Debian 12 installation were not run in this build environment.
