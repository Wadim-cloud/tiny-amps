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

### Sprint 5 — Hardening + Observability ✅
- Memory-bounded replay (dynamic array, capped at 1000)
- Backpressure: bounded subscriber channels with configurable drop policy
- Backpressure metrics integrated into `stats()`
- `filter_drop` stat tracks filtered messages
- C ABI layer (`amps/capi.odin`) exposes Python/ctypes interface
- 10k message roundtrip: 0 drops, 1.6 MB RSS

## Verified Commands

```bash
cd /home/ds/dev/tiny-amps
timeout 10 ./tiny-amps
AMPS_LIB_PATH=$PWD/libamps.so timeout 8 python py/tests/test_amps.py
odin build bench_swarmsim.odin -file -o:minimal -out:/tmp/bench-swarm && timeout 15 /tmp/bench-swarm
```

## Benchmark Results

| Test | Result |
|------|--------|
| 10k roundtrip | 0 drops, 1.6 MB RSS |
| Filter routing | 5,000/10,000 dropped before delivery |
| swarmsim A/B (80 agents × 50 rounds) | 98.75% drop reduction with filter |
| Python ctypes client | PASS pub/sub + filter |
| Replay buffer | PASS late-joiner delivery |

## North Star Goals
- Prove Odin delivers better results for swarmsim vs ZeroMQ backend
- Match or beat ZeroMQ PUB/SUB baseline throughput
- Beat it on per-message latency under filter
- No message loss at 10K concurrent subscribers
- Demonstrate content-based filtering before delivery (AMPS advantage)

## Repository
- Public repo: https://github.com/Wadim-cloud/tiny-amps
