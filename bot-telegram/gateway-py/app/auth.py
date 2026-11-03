"""Telegram administrator authorization helpers."""
from __future__ import annotations

from telegram import Update

from .config import AppConfig


def is_authorized(config: AppConfig, update: Update) -> tuple[bool, str]:
    if config.allow_unrestricted_access:
        return True, ""
    user_id = str(update.effective_user.id) if update.effective_user else ""
    chat_id = str(update.effective_chat.id) if update.effective_chat else ""
    chat_type = str(getattr(update.effective_chat, "type", "") or "").strip().lower()
    if config.admin_user_ids and user_id not in config.admin_user_ids:
        return False, "Akses ditolak: user Telegram belum terdaftar sebagai admin."
    if config.admin_chat_ids and chat_id not in config.admin_chat_ids:
        return False, "Akses ditolak: chat ini belum diizinkan untuk menu bot."
    if not config.admin_chat_ids and chat_type != "private":
        return False, "Akses ditolak: gunakan private chat dengan bot untuk command sensitif."
    return True, ""
