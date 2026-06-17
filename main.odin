package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "amps"

const NUM_MESSAGES = 10000
const TOPIC_A = "sensor.temp"
const TOPIC_B = "sensor.humidity"

trace :: "TinyAMPS"

// ------------------
// Warmup (make sure JIT/debug merges are done)
// ------------------
warmup :: proc(h: amps.Handle) {
	_, _ = amps.amp_stats(nil)
	_ = h
	time.sleep(50 * time.Millisecond)
}

// ------------------
// Benchmark 1: unfiltered fanout
// ------------------
BENCH_unfiltered_fanout :: proc() -> f64 {
	fmt.println("Benchmark 1: unfiltered fanout start")
	start := time.now()
	for i := 0; i < NUM_MESSAGES; i += 1 {
		topic := TOPIC_A
		if (i & 1) != 0 {
			topic = TOPIC_B
		}
		amps.amp_publish(nil, cstring(topic), []u8{uint8(i)})
	}
	elapsed := time.duration_seconds(time.now() - start) * 1e9
	fmt.printf("  elapsed ns      : %d\n", u64(elapsed))
	fmt.printf("  msgs/sec        : %.2f\n", f64(NUM_MESSAGES) / (elapsed / 1e9))
	return elapsed
}

// ------------------
// Benchmark 2: filtered delivery
// ------------------
 BENCH_filtered_delivery :: proc() -> f64 {
	fmt.println("Benchmark 2: filtered delivery start")
	start := time.now()
	for i := 0; i < NUM_MESSAGES; i += 1 {
		topic := TOPIC_A
		if (i & 1) != 0 {
			topic = TOPIC_B
		}
		amps.amp_publish(nil, cstring(topic), []u8{uint8(i)})
	}
	elapsed := time.duration_seconds(time.now() - start) * 1e9
	fmt.printf("  elapsed ns      : %d\n", u64(elapsed))
	fmt.printf("  msgs/sec        : %.2f\n", f64(NUM_MESSAGES) / (elapsed / 1e9))
	return elapsed
}

// ------------------
// Benchmark 3: start ramp (50 ms)
// ------------------
BENCH_start_ramp :: proc() -> f64 {
	fmt.println("Benchmark 3: start ramp")
	start := time.now()
	time.sleep(50 * time.Millisecond)
	return time.duration_seconds(time.now() - start) * 1e9
}

// ------------------
// Main entry
// ------------------
main :: proc() {
	_ = warmup(nil)
	b1 := BENCH_unfiltered_fanout()
	_ = b1
	b2 := BENCH_filtered_delivery()
	_ = b2
	b3 := BENCH_start_ramp()
	_ = b3
	fmt.println("done")
}
