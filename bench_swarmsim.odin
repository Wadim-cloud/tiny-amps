package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "amps"

NUM_AGENTS :: 80
PUBLISH_ROUNDS :: 50

run_scenario :: proc(filter: string) -> (sent: int, recv: int, drops: u64, fdrops: u64) {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "agent.*", filter=filter, buf_size=NUM_AGENTS * PUBLISH_ROUNDS)
	defer amps.unsubscribe(&h, 1)

	for r := 0; r < PUBLISH_ROUNDS; r += 1 {
		for i := 0; i < NUM_AGENTS; i += 1 {
			topic := fmt.tprintf("agent.%d", i)
			body := []byte{u8(i), u8(i >> 8)}
			ok := amps.publish(&h, amps.Message{topic = topic, body = body})
			if ok do sent += 1
		}
	}

	time.sleep(200 * time.Millisecond)

	for {
		_, ok := chan.try_recv(ch)
		if !ok do break
		recv += 1
	}

	_, drops, fdrops = amps.stats(&h)
	return
}

test_swarmsim_ab :: proc() {
	_, recv_nofilter, drops_nofilter, fdrops_nofilter := run_scenario("")
	want_no_filter := NUM_AGENTS * PUBLISH_ROUNDS
	if recv_nofilter != want_no_filter || fdrops_nofilter != 0 {
		fmt.printf("FAIL no-filter baseline: got %d recv, %d fdrops, want %d recv, 0 fdrops\n",
			recv_nofilter, fdrops_nofilter, want_no_filter)
		return
	}

	sent_f, recv_f, drops_f, fdrops_f := run_scenario("topic = \"agent.0\"")
	want_filter_recv := want_no_filter / NUM_AGENTS
	if recv_f == want_filter_recv && fdrops_f == u64(want_no_filter - want_filter_recv) {
		fmt.printf("PASS swarmsim A/B: no-filter=%d recv, filter=%d recv, filter_drops=%d\n",
			recv_nofilter, recv_f, fdrops_f)
	} else {
		fmt.printf("FAIL swarmsim A/B: no-filter=%d/%d, filter=%d/%d, fdrops=%d\n",
			recv_nofilter, want_no_filter,
			recv_f, want_filter_recv, fdrops_f)
	}
}

main :: proc() {
	test_swarmsim_ab()
	fmt.println("done")
}
