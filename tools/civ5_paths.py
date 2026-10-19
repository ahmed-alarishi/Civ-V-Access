"""Locate the Civ V install, the Civ V SDK, the Documents tree, and LLVM tools
on whatever machine the dev scripts run on, instead of baking in one
machine's paths. Mirrors tools/civ5-paths.ps1.

Import from a script under tools/ directly; from elsewhere, put tools/ on
sys.path first.
"""

import os
import re
import shutil
import sys

GAME_APP_NAME = "Sid Meier's Civilization V"
SDK_APP_NAME = "Sid Meier's Civilization V SDK"
GAME_APP_ID = 8930


def documents_dir():
    """The shell's Documents folder (CSIDL_PERSONAL), honoring redirection,
    the same lookup the game and the proxy DLL make. Off Windows, ~/Documents."""
    if os.name != "nt":
        return os.path.expanduser("~/Documents")
    import ctypes

    buf = ctypes.create_unicode_buffer(260)
    result = ctypes.windll.shell32.SHGetFolderPathW(None, 5, None, 0, buf)
    if result != 0:
        raise OSError(f"SHGetFolderPathW(CSIDL_PERSONAL) failed: {result:#x}")
    return buf.value


def civ5_docs_dir():
    """<Documents>/My Games/Sid Meier's Civilization 5 (logs, cache, MODS)."""
    return os.path.join(documents_dir(), "My Games", "Sid Meier's Civilization 5")


def _registry_value(root_name, key, value):
    if os.name != "nt":
        return None
    import winreg

    try:
        with winreg.OpenKey(getattr(winreg, root_name), key) as handle:
            return winreg.QueryValueEx(handle, value)[0]
    except OSError:
        return None


def steam_library_dirs():
    """Every Steam library root we can find, Steam's own install first."""
    roots = []

    def add(path):
        if path:
            path = os.path.normpath(path.strip().strip('"'))
            if path not in roots:
                roots.append(path)

    add(_registry_value("HKEY_CURRENT_USER", r"Software\Valve\Steam", "SteamPath"))
    add(_registry_value("HKEY_LOCAL_MACHINE", r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"))
    add(_registry_value("HKEY_LOCAL_MACHINE", r"SOFTWARE\Valve\Steam", "InstallPath"))
    program_files_x86 = os.environ.get("ProgramFiles(x86)")
    if program_files_x86:
        add(os.path.join(program_files_x86, "Steam"))

    for root in list(roots):
        vdf = os.path.join(root, "steamapps", "libraryfolders.vdf")
        try:
            with open(vdf, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        for match in re.finditer(r'"path"\s*"([^"]+)"', text):
            add(match.group(1).replace("\\\\", "\\"))
    return roots


def _steam_app_candidates(app_name):
    return [os.path.join(lib, "steamapps", "common", app_name) for lib in steam_library_dirs()]


def find_game_dir(explicit=None):
    """The Civ V install root. Checks the explicit path, then CIV5_DIR, then
    Steam's uninstall entry and libraries. Raises if none holds CivilizationV.exe."""
    candidates = [explicit, os.environ.get("CIV5_DIR")]
    for key in (
        rf"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App {GAME_APP_ID}",
        rf"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App {GAME_APP_ID}",
    ):
        candidates.append(_registry_value("HKEY_LOCAL_MACHINE", key, "InstallLocation"))
    candidates += _steam_app_candidates(GAME_APP_NAME)
    candidates = [c for c in candidates if c]
    for candidate in candidates:
        if os.path.isfile(os.path.join(candidate, "CivilizationV.exe")):
            return os.path.abspath(candidate)
    raise FileNotFoundError(
        "Could not find the Civilization V install. Set CIV5_DIR or pass the path explicitly. "
        f"Searched: {'; '.join(candidates) or '<none>'}"
    )


def find_sdk_source_dir(explicit=None):
    """The Civ V SDK's CvGameCoreSource folder. Checks the explicit path, then
    CIV5_SDK_DIR (the SDK install root), then the Steam libraries."""
    candidates = []
    if explicit:
        candidates.append(explicit)
    sdk_root = os.environ.get("CIV5_SDK_DIR")
    if sdk_root:
        candidates.append(os.path.join(sdk_root, "CvGameCoreSource"))
    candidates += [os.path.join(c, "CvGameCoreSource") for c in _steam_app_candidates(SDK_APP_NAME)]
    for candidate in candidates:
        if os.path.isdir(os.path.join(candidate, "CvGameCoreDLL_Expansion2")):
            return os.path.abspath(candidate)
    raise FileNotFoundError(
        "Could not find the Civ V SDK source. Set CIV5_SDK_DIR or pass the path explicitly. "
        f"Searched: {'; '.join(candidates) or '<none>'}"
    )


def find_llvm_tool(name):
    """An LLVM tool (e.g. llvm-objdump) from PATH, else the default LLVM install."""
    found = shutil.which(name)
    if found:
        return found
    exe = name if name.lower().endswith(".exe") or os.name != "nt" else name + ".exe"
    for base in (os.environ.get("ProgramFiles"), os.environ.get("ProgramW6432")):
        if base:
            candidate = os.path.join(base, "LLVM", "bin", exe)
            if os.path.isfile(candidate):
                return candidate
    raise FileNotFoundError(f"{name} not found on PATH or under Program Files\\LLVM\\bin. Install LLVM.")


if __name__ == "__main__":
    # Quick diagnostic: print what this machine resolves to.
    for label, fn in (
        ("documents", documents_dir),
        ("civ5 docs", civ5_docs_dir),
        ("game", find_game_dir),
        ("sdk source", find_sdk_source_dir),
    ):
        try:
            print(f"{label}: {fn()}")
        except Exception as exc:  # noqa: BLE001 - diagnostic only
            print(f"{label}: {exc}", file=sys.stderr)
