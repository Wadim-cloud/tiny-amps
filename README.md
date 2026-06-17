# Tiny AMPS

High-performance, in-memory pub/sub hub in [Odin](https://odin-lang.org/).  
Zero-copy `#pack` binary wire format. Content-based filtering before delivery.

> Named after AMPS's core differentiator: never enqueue a message a subscriber doesn't need.

---

## What it is

A single-process message router that lets many subscribers receive only the messages they want, filtered by topic *and* message body. Built to be embedded, benchmarked against ZeroMQ, and eventually used as the matching engine for swarmsim.

| | |
|---|---|
| **Language** | Odin (dev-2026-05-nightly:ea5175d) |
| **Output** | Static binary (`tiny-amps`) |
| **Next milestone** | `libamps.so` shared lib for Python/ctypes |

---

## Why Odin

- `#pack` gives zero-copy binary encoding by default—no JSON parser overhead.
- No GC pauses, no runtime. Predictable latency.
- `core:sync/chan` + `thread.run_with_data`线程，而无需C风格样板代码。
- 小二进制——整个condition功能块 < 300KB。

---

## Repository layout

```
amps/
  hub.odin          — Hub, Subscription, dispatch loop, TCP server
main.odin            — Tests: exact/wildcard/non-match routing
```

## Build

```bash
# Odin compiler must already be on PATH
export PATH="$HOME/.local/bin:$PATH"
export ODIN_ROOT="$HOME/.local/odin"
odin build . -o:minimal
./tiny-amps
```

### Run tests

```bash
timeout 3 ./tiny-amps
```

Expected output:

```
PASS exact route
PASS wildcard
PASS non-match
done
```

---

## Current sprint status

| Sprint | Status | Summary |
|--------|--------|---------|
| 1 — Core Hub | ✅ | In-memory exact + wildcard routing, channel dispatch, stats |
| 2 — Filter + Replay | 🔨 | Content filter + ring buffer replay |
| 3 — Python lib | ⏳ | `libamps.so` + ctypes bindings |
| 4 — Hardening | ⏳ | Backpressure, fuzz tests, benchmark report |

---

## Performance goals (Sprint 4)

- Match ZeroMQ PUB/SUB baseline throughput.
- Beat it on per-message latency under filter.
- No message loss at 10K concurrent subscribers.

---

## Decisions

| Choice | Why |
|--------|-----|
| `core:sync/chan` per subscriber | Typed, lock-free, Odin-native |
| Exact + wildcard prefix index | O(1) exact, O(k) wildcard |
| Filter before enqueue | Never deliver what nobody wants |
| Replay as bounded ring | Fixed memory, no GC pressure |
