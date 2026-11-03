# DLGST XRAY PANEL — BadVPN Launcher Fix

## Root cause
The installer checked the source launcher with `[[ -x ... ]]`. The full installer archive contained the launcher as mode 0644, so the source existed but was not marked executable. Setup therefore stopped with a false "not found/not executable" error.

## Permanent fix
- `opt/setup/install/badvpn.sh` now validates that the launcher source is a readable regular file (`-f` and `-r`).
- The install step already copies it to the runtime path with `install -m 0755`, so the installed launcher is executable regardless of source archive mode.
- Both BadVPN launcher scripts are marked executable in this source bundle.

## Apply to existing VPS
From the VPS root shell:

```bash
chmod 0755 /opt/autoscript/opt/setup/bin/badvpn-udpgw-launcher.sh
bash -n /opt/autoscript/opt/setup/install/badvpn.sh
```

Then rerun the DLGST setup using the same domain. This step is designed to be idempotent for already-installed components; inspect the setup log if any other stage reports an error.
