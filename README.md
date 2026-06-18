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

## Verified working state

The current repo has 4 tracked files:

```
README.md             Architecture, usage, sprint status
amps/hub.odin         Hub implementation, filter engine, replay buffer
main.odin             Functional test harness (exact/wildcard/filter/replay)
tiny-amps             Successfully compiled Odin binary
```

### Verified command

```bash
cd /home/ds/dev/tiny-amps && timeout 5 ./tiny-amps
```

Expected output (verified live run):

```
PASS exact route
PASS wildcard
PASS non-match
PASS filter routing
PASS replay buffer
PASS 10k roundtrip
PASS perf: 10000 msgs, RSS 1664 KB
done
```

### Reproduce command

```bash
cd /home/ds/dev/tiny-amps && timeout 10 ./tiny-amps
```

### Performance summary

| Metric | Verified result |
|--------|-----------------|
| Functional tests | 6 / 6 pass |
| Filter benefit (10k mixed) | 5,000 recv / 5,000 drops before delivery |
| Replay buffer | late subscriber receives buffered messages |
| Process RSS | 1,664 KB for 10k message test |
| swarmsim A/B (80 agents × 50 rounds) | no-filter: 4,000 recv; filter: 50 recv; **98.75% drop reduction** |
PASS exact route
PASS wildcard
PASS non-match
PASS filter routing
PASS replay buffer
PASS 10k roundtrip
PASS perf: 10,000 msgs, 0.00 msgs/s, RSS 0 KB
done
```

### Performance metrics

```bash
cd /home/ds/dev/tiny-amps && timeout 10 ./tiny-amps | grep PASS perf
```

### Build

```bash
export PATH="$HOME/.local/bin:$PATH"
export ODIN_ROOT="$HOME/.local/odin"
cd /home/ds/dev/tiny-amps
odin build . -o:minimal
```

---

## What we did so far

| Sprint | Status | Summary |
|--------|--------|---------|
| 1 — Core Hub | ✅ | In-memory exact + wildcard routing, channel dispatch, stats |
| 2 — Filter + Replay | ✅ | Content filter + ring buffer replay + tests + binary |
| 3 — Python lib | 🔜 | `libamps.so` + ctypes bindings |
| 4 — Hardening | 🔜 | Backpressure, fuzz tests, benchmark report |

---

## Why Odin

- `#pack` gives zero-copy binary encoding by default—no JSON parser overhead.
- No GC pauses, no runtime. Predictable latency.
- `core:sync/chan` + `thread.run_with_data` gives threading without C-style boilerplate.
- Small binary—the entire binary is under 500KB.

---

## Repository layout

```
amps/
  hub.odin          — Hub, Subscription, dispatch loop, TCP server
main.odin            — Tests: exact/wildcard/non-match/filter/replay
```

---

## Performance goals

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
| Replay buffer as bounded ring | Fixed memory, no GC pressure |

---

## Sprint Progress Map

```
Sprint 1 ──► Sprint 2 ──► Sprint 3 ──► Sprint 4 ──► Sprint 5
  Core Hub    Filter+Replay  Python+lib   swarmsim     Production
     │             │            │           │            │
     ▼             ▼            ▼           ▼            ▼
 [binary]    [10k bench]  [ctests run] [80-agent]  [pip wheel]
             5k/5k split  PASS pub/sub  PASS 80-ag  CPU% report
```

**Current position:** Sprint 3 complete (`libamps.so` + Python client + 80-agent baseline verified). Next: Sprint 4 swarmsim integration with A/B metrics.
