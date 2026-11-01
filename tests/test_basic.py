"""Basic unit tests for autoscript shared components."""
import sys
from pathlib import Path

# Add shared to path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "bot-telegram" / "shared"))


def test_shared_constants_paths():
    from constants import QUOTA_ROOT, ACCOUNT_INFO_ROOT
    assert QUOTA_ROOT == Path("/opt/quota")
    assert ACCOUNT_INFO_ROOT == Path("/opt/account")


def test_shared_constants_protocols():
    from constants import XRAY_PROTOCOLS, SSH_PROTOCOL, ALL_PROTOCOLS
    assert "vless" in XRAY_PROTOCOLS
    assert "vmess" in XRAY_PROTOCOLS
    assert "trojan" in XRAY_PROTOCOLS
    assert SSH_PROTOCOL == "ssh"
    assert SSH_PROTOCOL in ALL_PROTOCOLS
    assert all(p in ALL_PROTOCOLS for p in XRAY_PROTOCOLS)


def test_no_ip_license_guard_preflight():
    repo = Path(__file__).resolve().parents[1]
    run_source = (repo / "run.sh").read_text(encoding="utf-8")
    setup_source = (repo / "setup.sh").read_text(encoding="utf-8")
    manage_source = (repo / "opt/manage/app/main.sh").read_text(encoding="utf-8")
    bot_source = (repo / "bot-telegram/gateway-py/app/main.py").read_text(encoding="utf-8")
    assert "run_license_preflight" not in run_source
    assert "autoscript-license" not in run_source
    assert "autoscript_license_setup_preflight" not in setup_source
    assert "manage_license_guard_preflight" not in manage_source
    assert "check_runtime_license_blocking_message" not in bot_source
    assert (repo / "LICENSE").is_file()


def test_rate_limiter():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "account-portal"))
    from app.main import _rate_limit_check, _RATE_LIMIT_STORE, RATE_LIMIT_MAX_REQUESTS

    _RATE_LIMIT_STORE.clear()
    test_ip = "192.168.1.100"

    # Should allow up to max requests
    for _ in range(RATE_LIMIT_MAX_REQUESTS):
        assert _rate_limit_check(test_ip) is True

    # Should block after max
    assert _rate_limit_check(test_ip) is False

    # Different IP should still be allowed
    assert _rate_limit_check("10.0.0.1") is True

    _RATE_LIMIT_STORE.clear()




if __name__ == "__main__":
    test_shared_constants_paths()
    print("✓ test_shared_constants_paths")
    test_shared_constants_protocols()
    print("✓ test_shared_constants_protocols")
    test_rate_limiter()
    test_no_ip_license_guard_preflight()
    print("✓ test_no_ip_license_guard_preflight")
    print("✓ test_rate_limiter")
    print("\nAll tests passed.")
