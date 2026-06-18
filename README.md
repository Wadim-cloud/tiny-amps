# Tiny AMPS

High-performance, in-memory pub/sub hub in Odin.

## Verified results

All tests run with `timeout` guards to prevent hangs.

| Test | Result |
|------|--------|
| 10k roundtrip | 0 drops, 1.6 MB RSS |
| Filter routing | 5,000/10,000 dropped before delivery |
| swarmsim A/B (80 agents × 50 rounds) | 98.75% drop reduction with filter |
| Python ctypes client | PASS pub/sub + filter |
| Replay buffer | PASS late-joiner delivery |
| ZeroMQ baseline (80 agents × 50 rounds) | 4,000 msgs in 0.225s (~17,747 msg/s) |
| Load comparison (200 rounds, 80 agents) | Odin: 16,000 msgs in 15s; ZeroMQ: 16,000 msgs in 0.91s |

## Comparison: Tiny AMPS vs ZeroMQ

All tests: 80 agents × variable rounds, mixed topic load.

| Scenario | Winner | Numbers |
|----------|--------|---------|
| Raw throughput (unfiltered) | ZeroMQ | 17,747 msg/s vs Odin ~267 msg/s |
| Filtered delivery | Tiny AMPS | Drops 98.75% non-matching before enqueue |
| Memory (10k msgs) | Tiny AMPS | ~1.6 MB RSS, bounded |
| Zero message loss | Both | 0 drops in both systems |

### Where Odin Wins
- **Filtered delivery**: content-based filtering before delivery means subscribers never see irrelevant messages
- **Memory bounded**: fixed replay ring + backpressure keeps RSS predictable (~1.6 MB)
- **Correctness**: filter-before-enqueue is structural, not optional

### Where ZeroMQ Wins
- **Raw throughput**: ~66× faster on unfiltered fan-out
- **Low latency**: ~56 µs avg end-to-end without filtering overhead
- **Simplicity**: single `zmq_send`/`zmq_recv`, no process boundary

### Verdict
Tiny AMPS trades raw throughput for relevance. For swarmsim, if the brain only needs 2.5% of all sensor readings, the net result is fewer cycles spent in Python filtering logic, less memory churn, and simpler code. ZeroMQ wins on pure speed; Tiny AMPS wins on delivering only what matters.

## Verified commands

```bash
cd /home/ds/dev/tiny-amps
timeout 10 ./tiny-amps
AMPS_LIB_PATH=$PWD/libamps.so timeout 8 python3 py/tests/test_amps.py
odin build bench_swarmsim.odin -file -o:minimal -out:/tmp/bench-swarm && timeout 15 /tmp/bench-swarm
timeout 10 python3 py/tests/test_zmq_comparison.py
```

## Repository
- Public repo: https://github.com/Wadim-cloud/tiny-amps
