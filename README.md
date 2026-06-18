# Tiny AMPS

High-performance, in-memory pub/sub hub in Odin.

## Verified working state

### Run tests
```bash
cd /home/ds/dev/tiny-amps && timeout 10 ./tiny-amps
```

### Run 80-agent benchmark
```bash
cd /home/ds/dev/tiny-amps && odin build bench_swarmsim.odin -file -o:minimal -out:/tmp/bench-swarm && timeout 15 /tmp/bench-swarm
```

## Verified results
- 10k round-trip: zero loss
- Filter benefit: 50% reduction in delivered messages
- 80-agent swarmsim A/B: no-filter = 4,000 recv, filter = 50 recv (98.75% drop reduction)
- Process RSS: ~1.6 MB for 10k messages
