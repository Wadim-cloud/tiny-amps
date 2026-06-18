# Tiny AMPS

High-performance, in-memory pub/sub hub in Odin.

## Proven (measured with timeout guards)

| Result | Command |
|--------|---------|
| 10k roundtrip: 0 drops, ~1.6 MB RSS | `timeout 10 ./tiny-amps` |
| 80-agent A/B: 4,000 no-filter vs 50 filtered (98.75% drop) | `timeout 15 /tmp/bench-swarm` |
| Python/ctypes round-trip works | `AMPS_LIB_PATH=$PWD/libamps.so timeout 8 python py/tests/test_amps.py` |
| ZeroMQ baseline (80 agents × 50 rounds) | `timeout 10 python py/tests/test_zmq_comparison.py` |

## North star status

| Goal | Status | Numbers |
|------|--------|---------|
| Prove Odin better than ZeroMQ for swarmsim | Partial | Odin: 4,000 msgs in timeout 15; ZeroMQ: 4,000 msgs in 0.225s |
| Match/beat ZeroMQ throughput | TBD | Need same-duration comparison |
| Beat ZeroMQ on per-message latency under filter | TBD | Need latency histograms |
| No message loss at 10K subscribers | TBD | Only 80 tested so far |
| Content filtering before delivery | Proven | 98.75% drop under filter |

## Next measurements needed
1. Run same 80-agent test in same timeout for Odin + ZeroMQ side by side
2. Measure per-message latency with histogram (p50/p99)
3. 10k subscriber stress test
4. CPU % comparison under load
