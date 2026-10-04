"""A system notification and a sound for the calendar's reminders — what `notify-send`
and `pw-play` do on the Plasma side (calendar/package/contents/ui/main.qml, announce()).

The toast goes through PowerShell and the WinRT toast API: a few hundred milliseconds
once in a while, and no dependency. The sound is the standard library's winsound. Both
degrade to nothing where they cannot run, and nothing here raises into the server.
"""
import os
import subprocess
import sys
import threading

TOAST_SCRIPT = r"""
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$template = @"
<toast><visual><binding template="ToastGeneric"><text>{TITLE}</text><text>{TEXT}</text></binding></visual></toast>
"@
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("plaintop").Show($toast)
"""


def escape(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace('"', "&quot;"))


def toast(title, text):
    if os.name != "nt":
        print(f"plaintop notify: {title} — {text}", file=sys.stderr, flush=True)
        return False
    script = TOAST_SCRIPT.replace("{TITLE}", escape(title)).replace("{TEXT}", escape(text))

    def run():
        try:
            subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                           capture_output=True, timeout=15,
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except Exception as e:
            print(f"plaintop notify failed: {e!r}", file=sys.stderr, flush=True)
    threading.Thread(target=run, daemon=True).start()
    return True


def sound_path(name):
    """A reminder sound: "builtin:bell" is one of the calendar's own five (copied beside the
    service by win/build.py), anything else a file of the user's."""
    name = str(name or "").strip()
    if name.startswith("builtin:"):
        here = os.path.dirname(os.path.abspath(__file__))
        return os.path.join(here, "sounds", name[len("builtin:"):] + ".wav")
    return name


def play(path):
    """A .wav by path, asynchronously; anything else is ignored."""
    path = sound_path(path)
    if not path or not os.path.isfile(path):
        return False
    try:
        import winsound
    except ImportError:
        print(f"plaintop sound: {path}", file=sys.stderr, flush=True)
        return False
    try:
        winsound.PlaySound(path, winsound.SND_FILENAME | winsound.SND_ASYNC | winsound.SND_NODEFAULT)
        return True
    except RuntimeError as e:
        print(f"plaintop sound failed: {e!r}", file=sys.stderr, flush=True)
        return False


def notify(req):
    """The /notify request: {"title", "text", "sound": path or ""}."""
    req = req or {}
    shown = False
    if req.get("title") or req.get("text"):
        shown = toast(req.get("title", ""), req.get("text", ""))
    played = play(req.get("sound", ""))
    return {"ok": True, "toast": shown, "sound": played}
