"""Shared constants for autoscript Python components (bot-telegram, account-portal)."""
from pathlib import Path

# --- Data paths ---
QUOTA_ROOT = Path("/opt/quota")
ACCOUNT_INFO_ROOT = Path("/opt/account")

# --- Protocols ---
XRAY_PROTOCOLS = ("vless", "vmess", "trojan")
SSH_PROTOCOL = "ssh"
ALL_PROTOCOLS = XRAY_PROTOCOLS + (SSH_PROTOCOL,)


