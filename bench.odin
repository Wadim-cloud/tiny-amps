package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "amps"

NUM_MESSAGES :: 10000

send_recv_10k :: proc(filter: string) -> (sent: u64, received: u64, fdrops: u64) {
	h := amps.hub_init()
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.*", filter=filter, buf_size=10000)

	for i := 0; i < NUM_MESSAGES; i += 1 {
		topic := "sensor.temp"
		if (i & 1) != 0 {
			topic = "sensor.humidity"
		}
		body := []byte{u8(i), u8(i >> 8)}
		ok := amps.publish(&h, amps.Message{topic = topic, body = body})
		if ok do sent += 1
	}

	time.sleep(100 * time.Millisecond)

	for {
		_, ok := chan.try_recv(ch)
		if !ok do break
		received += 1
	}

	amps.unsubscribe(&h, 1)
	amps.hub_destroy(&h)

	_, _, fdrops = amps.stats(&h)
	return
}

test_filter_benefit :: proc() {
	_, _, drops_unfiltered := send_recv_10k("")
	if drops_unfiltered != 0 {
		fmt.println("FAIL no_filter fdrops:", drops_unfiltered)
		return
	}

	sent_f, recv_f, drops_f := send_recv_10k("topic = \"sensor.temp\"")
	expected_recv := u64(NUM_MESSAGES) / 2
	if recv_f == expected_recv && drops_f == expected_recv && sent_f == NUM_MESSAGES {
		fmt.printf("PASS filter: %d/%d sent, %d recv, %d drops\n",
			sent_f, NUM_MESSAGES, recv_f, drops_f)
	} else {
		fmt.printf("FAIL filter: sent=%d want=%d | recv=%d want=%d | drops=%d want=%d\n",
			sent_f, NUM_MESSAGES, recv_f, expected_recv, drops_f, expected_recv)
	}
}

main :: proc() {
	test_filter_benefit()
	fmt.println("done")
}
