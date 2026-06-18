# Why I Built Tiny AMPS

Most messaging systems hand you a firehose. You receive everything, then filter in user space. That works, but it costs you CPU, memory, and attention.

I wanted something different: a hub that drops irrelevant messages *before* they ever reach a subscriber. The way AMPS always should have worked.

## The spark

I was running an 80-agent multi-agent simulation (swarmsim). Every tick, every agent published state. The brain subscribed to everything and filtered in Python. On each tick, the brain cycled through ~4,000 messages just to find the 50 it actually cared about.

The math was clear: 98.75% of the work was unnecessary.

## The bet

What if the hub itself understood "agent.0 AND temp > 20"? What if filtering happened once, in a zero-copy, no-GC systems language, instead of N times in Python?

That bet is Tiny AMPS.

## The architecture

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

Two pipes doing what they do best:
- **ZeroMQ** handles the unreliable-network reality: reconnection, buffering, encryption.
- **Odin** handles the relevance problem: content-based routing before delivery, zero-copy, no GC pauses.

## The numbers

| Test | Result |
|------|--------|
| 10k round-trip | 0 drops, 1.6 MB RSS |
| Filter routing | 5,000/10,000 dropped before delivery |
| swarmsim A/B (80 agents × 50 rounds) | **98.75% message reduction** |
| ZeroMQ baseline (same load) | 4,000 msgs in 0.225s (~17,747 msg/s) |

Tiny AMPS isn’t faster than ZeroMQ at raw fan-out. It isn’t trying to be. It wins on relevance.

## Where this matters

**Multi-agent brains.** Agents publish state continuously. The brain only needs a fraction. Odin drops the rest. The brain stays small, fast, and simple.

**IoT thresholds.** 10,000 sensors, 1 Hz each. A filter like `temperature > 30 OR humidity > 90` collapses ingestion from 10M msgs/min to maybe 50K alert msgs. Cloud cost drops 95%.

**Financial signals.** 1M ticks/sec. A strategy only cares about one symbol and a price band. Odin delivers the signal; ZeroMQ delivers the noise. The strategy thinks less, reacts faster.

**Log routing.** 100K lines/sec. `level = "ERROR" AND service = "payment"` means the on-call engineer never even wakes up for DEBUG.

**Game events.** 1K players, 10K events/sec. Nearby-loot filters mean the client only processes what’s within 10 meters. Bandwidth down, CPU down, gameplay tighter.

## The edge

The edge isn’t speed. It’s **cognitive load**.

With ZeroMQ: every subscriber receives everything and filters in Python. For N subscribers, that’s N× the filtering work in user space.

With Tiny AMPS: the hub filters once in Odin. Subscribers get only what matches. For N subscribers, that’s 1× the filtering work in kernel space.

## What’s next

- AND/OR/NOT filters are already in place
- Numeric comparisons work
- TCP wire protocol hardening (CRC, heartbeat, max-message enforcement)
- Auto-reconnect with exponential backoff
- Health endpoint for observability
- pip-installable Python wheel with bundled `libamps.so`

## The north-star question

> Does the Odin-filtered path use measurably less CPU in the Python brain than an unfiltered ZeroMQ path?

We’ve proven message volume reduction. The next step is proving it in CPU time.

If you’re building a system where relevance matters more than raw throughput — where subscribers are expensive and publishers are many — the filter-before-delivery model is worth measuring.

That’s what this project is about.

---

*Karl Zylinski — gemmaro/powers*
