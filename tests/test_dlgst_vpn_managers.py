"""Regression tests for DLGST WireGuard and Shadowsocks managers."""

import datetime as dt
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]


def load_module(name, relative_path):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SS = load_module("dlgst_ssmanager_test", "opt/setup/bin/dlgst-ssmanager.py")
WG = load_module("dlgst_wgpanel_test", "opt/setup/bin/dlgst-wgpanel.py")


class ShadowsocksManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        SS.DATA = root / "accounts"
        SS.CONFIG = root / "configs"
        SS.LOCK_FILE = root / "run" / "manager.lock"

    def tearDown(self):
        self.temp.cleanup()

    def test_expired_port_stays_reserved_for_possible_renewal(self):
        SS.DATA.mkdir(parents=True)
        (SS.DATA / "olduser.json").write_text(json.dumps({"status": "expired", "port": 23456}))
        self.assertIn(23456, SS.used_ports())

    def test_renew_expired_account_reactivates_service(self):
        SS.DATA.mkdir(parents=True)
        SS.CONFIG.mkdir(parents=True)
        yesterday = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=2)).isoformat()
        account = {
            "username": "olduser", "port": 23456, "password": "oldpass",
            "expires_at": yesterday, "status": "expired", "method": SS.METHOD,
        }
        (SS.DATA / "olduser.json").write_text(json.dumps(account))
        actions = []
        SS.service_action = lambda username, action, check=True: actions.append((username, action)) or True
        SS.run = lambda command, check=True: subprocess.CompletedProcess(command, 0, "", "")

        SS.renew("olduser", 7)

        updated = json.loads((SS.DATA / "olduser.json").read_text())
        self.assertEqual(updated["status"], "active")
        self.assertGreater(dt.datetime.fromisoformat(updated["expires_at"]), dt.datetime.now(dt.timezone.utc))
        self.assertIn(("olduser", "enable"), actions)
        self.assertIn(("olduser", "start"), actions)
        self.assertTrue((SS.CONFIG / "olduser.json").is_file())

    def test_failed_expired_renewal_keeps_account_expired_and_disabled(self):
        SS.DATA.mkdir(parents=True)
        SS.CONFIG.mkdir(parents=True)
        yesterday = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=2)).isoformat()
        account = {
            "username": "olduser", "port": 23456, "password": "oldpass",
            "expires_at": yesterday, "status": "expired", "method": SS.METHOD,
        }
        (SS.DATA / "olduser.json").write_text(json.dumps(account))
        actions = []

        def fake_action(username, action, check=True):
            actions.append((username, action))
            if action == "start":
                raise RuntimeError("simulated start failure")
            return True

        SS.service_action = fake_action
        SS.run = lambda command, check=True: subprocess.CompletedProcess(command, 0, "", "")
        with self.assertRaises(RuntimeError):
            SS.renew("olduser", 7)

        restored = json.loads((SS.DATA / "olduser.json").read_text())
        self.assertEqual(restored["status"], "expired")
        self.assertIn(("olduser", "stop"), actions)
        self.assertIn(("olduser", "disable"), actions)


class WireGuardManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        WG.STATE = root / "state"
        WG.DATA = root / "accounts"
        WG.SETTINGS = WG.STATE / "settings.json"
        WG.LOCK = WG.STATE / "lock"
        WG.CONF = root / "etc" / "wg0.conf"
        WG.DATA.mkdir(parents=True)
        WG.STATE.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def test_server_keys_are_plain_text_and_recover_missing_public_key(self):
        WG.keys = lambda: ("private-key", "public-key")
        private = WG.ensure_server_keys()
        self.assertEqual(private, "private-key")
        self.assertEqual((WG.STATE / "server_private.key").read_text().strip(), "private-key")
        self.assertEqual((WG.STATE / "server_public.key").read_text().strip(), "public-key")

    def test_expiry_rolls_back_account_state_when_sync_fails(self):
        expired = (dt.date.today() - dt.timedelta(days=1)).isoformat()
        account = {"username": "olduser", "status": "active", "expires_at": expired}
        (WG.DATA / "olduser.json").write_text(json.dumps(account))
        calls = {"count": 0}

        def fake_sync():
            calls["count"] += 1
            if calls["count"] == 1:
                raise RuntimeError("simulated sync failure")

        WG.sync = fake_sync
        with self.assertRaises(RuntimeError):
            WG.expire()

        restored = json.loads((WG.DATA / "olduser.json").read_text())
        self.assertEqual(restored["status"], "active")
        self.assertEqual(calls["count"], 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
