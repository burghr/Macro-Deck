import subprocess
import platform

MACOS = platform.system() == "Darwin"


def check_accessibility() -> bool:
    if not MACOS:
        return True
    try:
        from ApplicationServices import AXIsProcessTrusted
        return bool(AXIsProcessTrusted())
    except Exception:
        return True


def request_accessibility() -> bool:
    """Trigger the macOS 'wants to control your computer' system dialog."""
    if not MACOS:
        return True
    try:
        from ApplicationServices import AXIsProcessTrustedWithOptions
        return bool(AXIsProcessTrustedWithOptions({"AXTrustedCheckOptionPrompt": True}))
    except Exception:
        _open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        return False


def check_input_monitoring() -> bool:
    if not MACOS:
        return True
    try:
        from ApplicationServices import CGPreflightListenEventAccess
        return bool(CGPreflightListenEventAccess())
    except Exception:
        return True


def request_input_monitoring():
    """Trigger the macOS 'wants to monitor keyboard input' system dialog."""
    if not MACOS:
        return
    try:
        from ApplicationServices import CGRequestListenEventAccess
        CGRequestListenEventAccess()
    except Exception:
        _open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")


def _open(url: str):
    subprocess.run(["open", url], check=False)


def needs_any() -> bool:
    return not check_accessibility() or not check_input_monitoring()
