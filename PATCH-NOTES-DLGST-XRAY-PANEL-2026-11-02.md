# DLGST XRAY PANEL — Patch Notes (2 November 2026)

## Scope

This patch integrates and hardens the WireGuard and Shadowsocks components in the supplied source tree. It is a source-only installer bundle; it does not contain customer account databases, generated WireGuard keys, server credentials, or runtime configuration.

## Changes

1. **Independent component provisioning**
   - WireGuard and Shadowsocks are attempted independently during setup.
   - A WireGuard provisioning failure no longer skips the Shadowsocks installation attempt, and vice versa.
   - Each component validates its backend, dependencies, templates, systemd timer, and runtime activation.

2. **Shadowsocks account lifecycle**
   - All manager operations now share one process lock, including create, delete, renew, reset, list, and expiry processing.
   - Expired accounts can be renewed and their systemd service is re-enabled and started.
   - Expired account ports remain reserved until the account is deleted, preventing port collisions if an old account is renewed later.
   - Expiry failures are returned as non-zero so systemd does not report a failed expiry pass as successful.
   - Create/reset/renew paths include rollback handling for service-operation failures.

3. **WireGuard account/runtime lifecycle**
   - Server key files are written atomically as plain WireGuard key text; a missing public-key file can be reconstructed from the private key.
   - Client and server configuration files are written atomically with restrictive permissions.
   - Expired addresses remain reserved until the account is deleted, preventing address reuse followed by renewal collision.
   - Add, delete, renew, reset, and expiry updates attempt rollback when runtime synchronization fails.

4. **WireGuard firewall recovery**
   - The dedicated `ip dlgst_wireguard` nftables table is replaced when stale state remains after an unclean shutdown, instead of permanently blocking `wg-quick` startup.

5. **Installer sanity checks**
   - Post-install sanity now verifies WireGuard interface/timer/NAT state and Shadowsocks backend/template/timer state.
   - Existing active Shadowsocks accounts must have their corresponding systemd instance active.

6. **Portable source bundle execution**
   - Added `.dlgst-source-bundle` marker and updated `run.sh` so an extracted source archive can run locally without requiring `.git` metadata.
   - Existing local `opt/setup/core/logging.sh` change (`log()` helper) was preserved.

## Fresh VPS behavior

The bundle intentionally excludes `/opt/account` runtime data and `.git` metadata. It installs a new server configuration and does not restore customer accounts from the source archive.

After extracting the archive to `/opt/autoscript`, run:

```bash
cd /opt/autoscript
bash run.sh
```

The bundle marker makes `run.sh` select the extracted local source tree. Run as root on a supported Debian/Ubuntu VPS and complete the interactive domain/setup prompts.

## Validation performed in the build workspace

- `bash tools/test-noninteractive.sh` — passed.
- `python3 tests/test_dlgst_vpn_managers.py` — 5 regression tests passed.
- `pytest -q tests` — 9 tests passed (including the existing test suite).
- Bash syntax checks for modified shell scripts — passed.
- Python bytecode compilation for modified managers — passed.
- ShellCheck was not available in the build workspace, so ShellCheck lint was skipped.
- A real fresh Debian 12 VPS installation, reboot test, and live client connectivity test were **not** performed here. Those remain required before production rollout.
