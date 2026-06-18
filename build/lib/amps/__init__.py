"""
Tiny AMPS Python client (ctypes).

Expected layout: put `libamps.so` in one of these locations:
- directory on `LD_LIBRARY_PATH`
- same folder as this module (`py/amps/`)
- repo root (default install layout)
Override with `AMPS_LIB_PATH` env var to point at an explicit `.so`.
"""
from __future__ import annotations

import ctypes
import ctypes.util
import os
import time
from typing import Optional, Tuple

_LIB_NAME = "libamps.so"


def _find_lib() -> str:
    env_override = os.environ.get("AMPS_LIB_PATH")
    if env_override and os.path.exists(env_override):
        return env_override

    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        ctypes.util.find_library("amps"),
        os.path.join(here, "..", "..", _LIB_NAME),
        os.path.join(here, "..", _LIB_NAME),
        _LIB_NAME,
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    raise FileNotFoundError(f"{_LIB_NAME} not found")


class TinyAMPS:
    def __init__(self) -> None:
        self._lib = ctypes.CDLL(_find_lib())

        self._lib.amps_init.restype = ctypes.c_void_p
        self._lib.amps_init.argtypes = []

        self._lib.amps_close.restype = None
        self._lib.amps_close.argtypes = [ctypes.c_void_p]

        self._lib.amps_publish.restype = ctypes.c_bool
        self._lib.amps_publish.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_ubyte),
            ctypes.c_size_t,
        ]

        self._lib.amps_subscribe.restype = ctypes.c_uint32
        self._lib.amps_subscribe.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_int,
        ]

        self._lib.amp_unsubscribe.restype = None
        self._lib.amp_unsubscribe.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

        self._lib.amps_stats.restype = None
        self._lib.amps_stats.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_uint64),
            ctypes.POINTER(ctypes.c_uint64),
            ctypes.POINTER(ctypes.c_uint64),
        ]

        self.handle: Optional[int] = self._lib.amps_init()
        if not self.handle:
            raise RuntimeError("amps_init failed")

    def close(self) -> None:
        if self.handle:
            self._lib.amps_close(self.handle)
            self.handle = None

    def publish(self, topic: str, body: bytes) -> bool:
        if not self.handle:
            raise RuntimeError("client is closed")
        if not isinstance(body, (bytes, bytearray)):
            raise TypeError("body must be bytes")
        buf = (ctypes.c_ubyte * len(body)).from_buffer_copy(body)
        return bool(
            self._lib.amps_publish(
                self.handle,
                topic.encode("utf-8"),
                buf,
                ctypes.c_size_t(len(body)),
            )
        )

    def subscribe(self, topic: str, filter_text: str = "", buf_size: int = 4096) -> int:
        if not self.handle:
            raise RuntimeError("client is closed")
        return int(
            self._lib.amps_subscribe(
                self.handle,
                topic.encode("utf-8"),
                filter_text.encode("utf-8"),
                ctypes.c_int(buf_size),
            )
        )

    def unsubscribe(self, sub_id: int) -> None:
        if not self.handle:
            return
        self._lib.amp_unsubscribe(self.handle, ctypes.c_uint32(sub_id))

    def stats(self) -> Tuple[int, int, int]:
        if not self.handle:
            return (0, 0, 0)
        msgs = ctypes.c_uint64(0)
        drops = ctypes.c_uint64(0)
        fdrops = ctypes.c_uint64(0)
        self._lib.amps_stats(self.handle, ctypes.byref(msgs), ctypes.byref(drops), ctypes.byref(fdrops))
        return int(msgs.value), int(drops.value), int(fdrops.value)


__all__ = ["TinyAMPS"]
