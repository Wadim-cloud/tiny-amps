# Tiny AMPS

High-performance, in-memory pub/sub hub in Odin.

## Verified Steps

### Sprint 1 — Core Hub ✅
- Binary `tiny-amps` builds and runs
- 3/3 tests pass (exact/wildcard/non-match)

### Sprint 2 — Filter + Replay ✅
- Filter engine + replay buffer added to `amps/hub.odin`
- 10k roundtrip verified: zero message loss
- Filter benefit: 5,000/10,000 messages dropped before delivery (50% under mixed load)

### Sprint 3 — Python lib + Shared lib ✅
- `libamps.so` built via Odin shared-library build
- `py/amps/__init__.py` ctypes client implemented
- Python regression tests pass (`py/tests/test_amps.py`)
- 80-agent baseline verified: 80 sent, 80 recv, 0 fdrops

### Sprint 4 — swarmsim Integration ✅
- 80-agent A/B benchmark (`bench_swarmsim.odin`) verified
- No-filter baseline: 4,000 recv, 0 fdrops (80 agents × 50 rounds)
- Filter `topic = "agent.0"`: 50 recv, 3,950 fdrops
- **Filter benefit: 98.75% message reduction before delivery**

## Active Work

### Sprint 5 — Hardening + Observability (in progress)
- Health endpoint (text protocol on control port)
- Backpressure: bounded subscriber channels with configurable drop policy
- Structured error reporting from C ABI (error codes, not just bool)
- Fuzz test filter parser with 1M random messages
- Memory-bounded replay (fixed ring, not dynamic array)

## Blindspots
1. Filter language minimal — no AND/OR/NOT, no numeric operators
2. Replay best-effort — no backpressure, no ordering under concurrent publishers
3. Python GIL interaction — ctypes thread safety not fully verified
4. No persistence — in-memory only; restart loses state
5. TCP transport stubbed — not production-ready wire protocol

## Verified Commands

```bash
cd /home/ds/dev/tiny-amps
timeout 10 ./tiny-amps
AMPS_LIB_PATH=$PWD/libamps.so timeout 8 python py/tests/test_amps.py
odin build bench_swarmsim.odin -file -o:minimal -out:/tmp/bench-swarm && timeout 15 /tmp/bench-swarm
```

## Repository
- Public repo: https://github.com/Wadim-cloud/tiny-amps
