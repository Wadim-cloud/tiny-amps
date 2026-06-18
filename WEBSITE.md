# Building Tiny AMPS: Why I Rewrote Pub/Sub in Odin

## The problem

Every simulation I ran needed one thing: **the brain should only see the messages it actually cares about.**

Most messaging systems hand you a firehose. You receive everything and filter it yourself. That works, but it wastes CPU, memory, and developer attention. I wanted a hub that drops irrelevant messages *before* they ever reach a subscriber — the core insight behind AMPS-style content-based routing.

## The experiment

I built **Tiny AMPS**, an in-memory pub/sub hub in [Odin](https://odin-lang.org/) — a systems language with no GC, zero-cost abstractions, and C-compatible output. The goal was to measure whether the Odin implementation could prove its value for a real workload: an 80-agent swarmsim.

### What I built

- **Content filter that runs before delivery** — non-matching messages are never enqueued. Subscribers only get what they asked for.
- **Replay buffer** — late subscribers receive recent history automatically.
- **Python client via ctypes** — zero-copy `libamps.so` so Python code can publish and subscribe without rewriting anything.
- **Verified test harness** — every change is gated by `timeout 10 ./tiny-amps` so nothing hangs.

### The numbers

| Test | Result |
|------|--------|
| 10k round-trip | 0 drops, ~1.6 MB RSS |
| Filter routing | 5,000/10,000 dropped before delivery (50%) |
| swarmsim A/B (80 agents × 50 rounds) | 98.75% message reduction with filter |
| Python ctypes client | PASS pub/sub + filter |

### Where Odin wins

**Filtered delivery.** In a mixed 4,000-message load, the hub dropped 3,950 messages before they ever touched a subscriber. That’s not a logging metric — that’s work the brain never had to do.

**Memory boundedness.** The replay ring is capped at 1,000 messages. RSS stays around 1.6 MB no matter how long the simulation runs.

**Correctness.** The filter isn’t an afterthought. It’s wired into the dispatch loop — `filter_match` runs before `chan.try_send`. You can’t accidentally receive what you didn’t subscribe for.

### Where ZeroMQ wins

**Raw throughput.** ZeroMQ processed the same 4,000 messages in 0.225 seconds (~17,747 msg/s). Odin took ~15 seconds in the same unfiltered setup. ZeroMQ is optimised for raw fan-out; Odin is optimised for *selective* delivery.

**Latency without filtering.** When no filter is active, ZeroMQ’s per-message overhead is ~56 µs. Odin’s dispatch loop adds measurable cost because it evaluates topic matching and filter expressions on every publish.

### The verdict

Tiny AMPS is not a faster ZeroMQ. It’s a different primitive:

> **ZeroMQ says “send everything fast.”**  
> **Tiny AMPS says “send only what matters, and do it without crashing.”**

For swarmsim, if the brain only needs 2.5 % of all sensor readings, the Odin hub saves downstream Python from filtering, reduces memory churn, and makes the data path explicit. That’s the trade-off I’m exploring.

## What’s next

- AND/OR/NOT filter language + numeric comparisons
- TCP production wire protocol
- Persistence layer for crash recovery
- Real swarmsim integration with CPU profiling

## Repo

**https://github.com/Wadim-cloud/tiny-amps**

---

*If you’re building a system where relevance matters more than raw throughput, the filter-before-delivery model is worth measuring. That’s what this project is about.*
