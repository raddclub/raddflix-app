from __future__ import annotations
import importlib
import pkgutil
from pathlib import Path
from .base import SitePlugin
_plugins: dict[str, type[SitePlugin]] = {}
def _discover():
    pkg_dir = Path(__file__).parent
    for _, module_name, _ in pkgutil.iter_modules([str(pkg_dir)]):
        if module_name.startswith("_") or module_name == "base":
            continue
        try:
            # Import relative to this package (hub.sites.*)
            mod = importlib.import_module(f"{__name__}.{module_name}")
            for attr in dir(mod):
                obj = getattr(mod, attr)
                try:
                    if (
                        isinstance(obj, type)
                        and issubclass(obj, SitePlugin)
                        and obj is not SitePlugin
                    ):
                        _plugins[obj.name] = obj
                except TypeError:
                    pass
        except Exception as e:
            print(f"[sites] Warning: could not load {__name__}.{module_name}: {e}")
_discover()
def get_plugin(name: str) -> SitePlugin:
    cls = _plugins.get(name)
    if cls is None:
        # Case-insensitive fallback — tolerate "vegamovies" → "VegaMovies" etc.
        name_lower = name.lower()
        for key, candidate in _plugins.items():
            if key.lower() == name_lower:
                cls = candidate
                break
    if cls is None:
        raise ValueError(
            f"No site plugin named '{name}'. Available: {sorted(_plugins.keys())}"
        )
    return cls()
def get_plugins_in_order(order: list[str]) -> list[SitePlugin]:
    result  = []
    ordered = set()
    for name in order:
        cls = _plugins.get(name)
        if cls:
            result.append(cls())
            ordered.add(name)
        else:
            print(f"[sites] Warning: plugin '{name}' not found, skipping.")
    for name, cls in _plugins.items():
        if name not in ordered:
            result.append(cls())
    return result
def list_plugins() -> list[dict]:
    return [
        {"name": p.name, "description": p.description, "version": p.version}
        for p in _plugins.values()
    ]
def reload_plugins():
    _plugins.clear()
    _discover()