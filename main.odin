package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "amps"

NUM_MESSAGES :: 10000
TOPIC_A :: "sensor.temp"
TOPIC_B :: "sensor.humidity"

test_exact_routing :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.temp", filter="", buf_size=8)
	defer amps.unsubscribe(&h, 1)

	amps.publish(&h, amps.Message{topic = "sensor.temp", body = []byte{1}})
	time.sleep(100 * time.Millisecond)

	m, ok := chan.try_recv(ch)
	if ok && m.topic == "sensor.temp" {
		fmt.println("PASS exact route")
	} else {
		fmt.println("FAIL exact route:", m.topic, ok)
	}
}

test_wildcard_routing :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.*", filter="", buf_size=8)
	defer amps.unsubscribe(&h, 1)

	amps.publish(&h, amps.Message{topic = "sensor.temp", body = []byte{1}})
	amps.publish(&h, amps.Message{topic = "sensor.humidity", body = []byte{2}})
	time.sleep(100 * time.Millisecond)

	count := 0
	for {
		_, ok := chan.try_recv(ch)
		if !ok do break
		count += 1
	}

	if count == 2 {
		fmt.println("PASS wildcard")
	} else {
		fmt.println("FAIL wildcard count:", count)
	}
}

test_non_match :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "other.*", filter="", buf_size=8)
	defer amps.unsubscribe(&h, 1)

	amps.publish(&h, amps.Message{topic = "sensor.temp", body = []byte{1}})
	time.sleep(100 * time.Millisecond)

	_, ok := chan.try_recv(ch)
	if !ok {
		fmt.println("PASS non-match")
	} else {
		fmt.println("FAIL non-match received")
	}
}

test_filter_routing :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.*", filter="topic = \"sensor.temp\"", buf_size=8)
	defer amps.unsubscribe(&h, 1)

	amps.publish(&h, amps.Message{topic = "sensor.temp", body = []byte{1}})
	amps.publish(&h, amps.Message{topic = "sensor.humidity", body = []byte{2}})
	time.sleep(100 * time.Millisecond)

	msgs, drops, fdrops := amps.stats(&h)
	count := 0
	for {
		m, ok := chan.try_recv(ch)
		if !ok do break
		if m.topic == "sensor.temp" {
			count += 1
		} else {
			fmt.println("FAIL filter got wrong topic:", m.topic)
		}
	}

	if count == 1 && fdrops == 1 {
		fmt.println("PASS filter routing")
	} else {
		fmt.println("FAIL filter routing: count=", count, "fdrops=", fdrops)
	}
}

test_replay_buffer :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	amps.publish(&h, amps.Message{topic = "sensor.temp", body = []byte{1}})
	amps.publish(&h, amps.Message{topic = "sensor.humidity", body = []byte{2}})
	time.sleep(50 * time.Millisecond)

	ch, _ := amps.subscribe(&h, "sensor.*", filter="", buf_size=8)
	defer amps.unsubscribe(&h, 2)

	time.sleep(100 * time.Millisecond)

	count := 0
	for {
		_, ok := chan.try_recv(ch)
		if !ok do break
		count += 1
	}

	if count == 2 {
		fmt.println("PASS replay buffer")
	} else {
		fmt.println("FAIL replay buffer count:", count)
	}
}

main :: proc() {
	test_exact_routing()
	test_wildcard_routing()
	test_non_match()
	test_filter_routing()
	test_replay_buffer()
	fmt.println("done")
}
