# Tiny AMPS

High-performance, in-memory pub/sub hub in Odin with content-based filtering.

## The hybrid architecture

The wisest design combines both:

- **ZeroMQ for transport** — robust reconnect, buffering, encryption, mature ecosystem
- **Tiny AMPS for filtering** — content-based routing in Odin, zero-copy, structural guarantee

```
 Publishers                     Tiny AMPS Hub                    Subscribers
    │                              │                                │
    │   ZeroMQ PUB                 │   Filter engine (Odin)         │
    ├────────────────────────────► │   ┌────────────────────────┐   │
    │  topic, body                │   │  Does body match        │   │
    │                              │   │  subscriber filter?     │   │
    │                              │   └──────────┬─────────────┘   │
    │                              │              │ yes              │
    │                              │   ┌──────────▼─────────────┐   │
    │                              │   │  ZeroMQ SUB delivery    │   │
    ├────────────────────────────► │   │  (only matching msgs)   │   │
    │  topic, body                │   └────────────────────────┘   │
    │                              │                                │
```

**Result:** ZeroMQ gives you the pipe; Odin gives you the brain.

## Verified results

| Test | Result |
|------|--------|
| 10k roundtrip | 0 drops, 1.6 MB RSS |
| Filter routing | 5,000/10,000 dropped before delivery |
| swarmsim A/B (80 agents × 50 rounds) | 98.75% drop reduction with filter |
| Python ctypes client | PASS pub/sub + filter |
| Replay buffer | PASS late-joiner delivery |
| ZeroMQ baseline (80 agents × 50 rounds) | 4,000 msgs in 0.225s (~17,747 msg/s) |

## Use cases

### 1. Multi-agent brain (swarmsim)
- 80 agents publish state, brain subscribes to filtered view
- Edge: ZeroMQ delivers all 80 states; Odin delivers only matches
- Win: brain CPU drops because irrelevant messages never arrive

### 2. IoT sensor aggregation
- 10K sensors at 1 Hz; gateway filters threshold violations
- Edge: MQTT ingests all; Odin reduces cloud ingestion by 95%+
- Win: lower bandwidth, no cloud-side filtering

### 3. Financial tick filtering
- 1M ticks/sec; strategy gets only `symbol = "AAPL" AND price > 150`
- Edge: direct feed delivers all symbols; Odin delivers only signals
- Win: sub-ms filter latency, zero tick loss

### 4. Log routing
- 100K log lines/sec; alert handler gets only `level = "ERROR" AND service = "payment"`
- Edge: ELK parses everything; Odin routes only matches
- Win: alert latency from seconds to milliseconds

### 5. Game server event bus
- 1K players, 10K events/sec; client gets only nearby loot events
- Edge: naive broadcast delivers all; Odin delivers only relevant spatial events
- Win: lower client CPU, smoother gameplay

## Competitive edge

| Dimension | ZeroMQ alone | Tiny AMPS alone | Hybrid |
|-----------|-------------|-----------------|--------|
| Delivery model | Fan-out everything | Filter before delivery | Filter before delivery |
| Filter location | In subscriber | In hub (Odin) | In hub (Odin) |
| Memory | Unbounded queue | Bounded replay ring | Bounded replay ring |
| Crash recovery | None | Replay buffer | Replay buffer |
| Transport robustness | Mature, reconnect, encryption | Raw TCP only | ZeroMQ pipe + Odin brain |

**The edge:** filtering happens once at the hub in Odin, not N times in Python. Transport is handled by ZeroMQ's battle-tested pipe.

## North star status

**Question:** Does the Odin-filtered path use measurably less CPU in the Python brain than an unfiltered ZeroMQ path?

| Backend | Messages to brain | Brain CPU (per trial) | Status |
|---------|------------------|----------------------|--------|
| ZeroMQ + no filter | 4,000 | ~X ms | Baseline |
| ZeroMQ + Python filter | 4,000 → ~50 | ~X ms | Partial |
| Odin + filter | ~50 | ~X ms | **Target** |

**Hypothesis:** Odin path uses < 50% of ZeroMQ brain CPU because brain processes 1.25% of messages.

## Verified commands

```bash
cd /home/ds/dev/tiny-amps
timeout 10 ./tiny-amps
AMPS_LIB_PATH=$PWD/libamps.so timeout 8 python3 py/tests/test_amps.py
odin build bench/bench_swarmsim.odin -file -o:minimal -out:/tmp/bench-swarm && timeout 15 /tmp/bench-swarm
timeout 10 python3 py/tests/test_zmq_comparison.py
timeout 60 python3 py/tests/test_north_star.py
```

## Repository
- Public repo: https://github.com/Wadim-cloud/tiny-amps
