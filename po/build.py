#!/usr/bin/env python3
"""Compile one widget's catalogs: po/<lang>/<domain>.po → <outdir>/<lang>/LC_MESSAGES/<domain>.mo

Used by install.sh, which builds into the plasmoid package (contents/locale), and by the
window hosts' setup.py, which deploys the same files into ~/.local/share/locale. This
domain's old .mo files are removed first, so a language dropped from po/ does not linger
in a package — and only this domain's, so two domains can share an output directory.
Only msgfmt is needed here; refreshing the catalogs is extract.py's job.

    python3 po/build.py plasma_applet_org.s1dd1.plaintop monitor/package/contents/locale
"""
import subprocess
import sys
from pathlib import Path

PO = Path(__file__).resolve().parent


def build(domain, outdir):
    """Returns the .mo files written; raises when msgfmt is missing or rejects a catalog."""
    outdir = Path(outdir)
    for old in outdir.glob(f"*/LC_MESSAGES/{domain}.mo"):
        old.unlink()
    built = []
    for po in sorted(PO.glob(f"*/{domain}.po")):
        mo = outdir / po.parent.name / "LC_MESSAGES" / f"{domain}.mo"
        mo.parent.mkdir(parents=True, exist_ok=True)
        # --check: a translation that drops or reorders a %1 fails here, not on screen.
        subprocess.run(["msgfmt", "--check", "-o", str(mo), str(po)], check=True)
        built.append(mo)
    return built


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1].strip())
    try:
        mos = build(sys.argv[1], sys.argv[2])
    except FileNotFoundError:
        sys.exit("  ✗ нет msgfmt — поставь gettext")
    except subprocess.CalledProcessError as e:
        sys.exit(f"  ✗ каталог не собрался: {e.cmd[-1]}")
    langs = sorted(m.parent.parent.name for m in mos)
    print(f"  ✓ переводы {sys.argv[1]}: {', '.join(langs) or 'нет'}")
