package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "core:os"
import "core:mem"
import "core:strings"
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

test_10k_roundtrip :: proc() {
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.*", filter="", buf_size=10000)
	defer amps.unsubscribe(&h, 1)

	total := 0
	for i := 0; i < 10000; i += 1 {
		topic := "sensor.temp"
		if (i & 1) != 0 {
			topic = "sensor.humidity"
		}
		body := []byte{u8(i), u8(i >> 8)}
		ok := amps.publish(&h, amps.Message{topic = topic, body = body})
		if ok do total += 1
	}

	received := 0
	for received < total {
		_, ok := chan.try_recv(ch)
		if ok do received += 1
	}

	if received == total && total == 10000 {
		fmt.println("PASS 10k roundtrip")
	} else {
		fmt.println("FAIL 10k roundtrip:", received, total)
	}
}

rss_bytes :: proc() -> u64 {
	data, err := os.read_entire_file("/proc/self/status", context.allocator)
	if err != nil || len(data) == 0 do return 0

	text := string(data)
	lines := strings.split(text, "\n")
	for line in lines {
		if strings.has_prefix(line, "VmRSS:") {
			i := 0
			for i < len(line) {
				c := line[i]
				if c >= '0' && c <= '9' {
					num := 0
					for i < len(line) && line[i] >= '0' && line[i] <= '9' {
						num = num * 10 + int(line[i] - '0')
						i += 1
					}
					return u64(num) * 1024
				}
				i += 1
			}
		}
	}
	return 0
}

test_perf :: proc() {
	hub := amps.hub_init()
	defer amps.hub_destroy(&hub)
	amps.start_dispatch(&hub)

	ch, _ := amps.subscribe(&hub, "sensor.*", filter="", buf_size=10000)
	defer amps.unsubscribe(&hub, 1)

	before := rss_bytes()
	N := 10000
	total := 0
	for i := 0; i < N; i += 1 {
		topic := "sensor.temp"
		if (i & 1) != 0 {
			topic = "sensor.humidity"
		}
		body := []byte{u8(i), u8(i >> 8)}
		ok := amps.publish(&hub, amps.Message{topic = topic, body = body})
		if ok do total += 1
	}
	received := 0
	for received < total {
		_, ok := chan.try_recv(ch)
		if ok do received += 1
	}
	after := rss_bytes()

	if received == total && total == N {
		fmt.printf("PASS perf: %d msgs, RSS %d KB\n", total, (after - before) / 1024)
	} else {
		fmt.println("FAIL perf incomplete:", received, total)
	}
}

test_filter_benefit :: proc() {
	N := 10000
	h := amps.hub_init()
	defer amps.hub_destroy(&h)
	amps.start_dispatch(&h)

	ch, _ := amps.subscribe(&h, "sensor.*", filter="", buf_size=10000)
	defer amps.unsubscribe(&h, 1)

	total := 0
	for i := 0; i < N; i += 1 {
		topic := "sensor.temp"
		if (i & 1) != 0 {
			topic = "sensor.humidity"
		}
		body := []byte{u8(i), u8(i >> 8)}
		ok := amps.publish(&h, amps.Message{topic = topic, body = body})
		if ok do total += 1
	}

	received := 0
	for received < total {
		_, ok := chan.try_recv(ch)
		if ok do received += 1
	}

	_, _, fdrops_unfiltered := amps.stats(&h)
	if received == total && fdrops_unfiltered == 0 {
		fmt.printf("PASS no_filter: %d sent, %d received, 0 filter drops\n", total, received)
	} else {
		fmt.printf("FAIL no_filter: %d received, %d fdrops\n", received, fdrops_unfiltered)
	}

	h = amps.hub_init()
	amps.start_dispatch(&h)
	ch, _ = amps.subscribe(&h, "sensor.*", filter="topic = \"sensor.temp\"", buf_size=10000)
	defer amps.unsubscribe(&h, 1)

	total = 0
	for i := 0; i < N; i += 1 {
		topic := "sensor.temp"
		if (i & 1) != 0 {
			topic = "sensor.humidity"
		}
		body := []byte{u8(i), u8(i >> 8)}
		ok := amps.publish(&h, amps.Message{topic = topic, body = body})
		if ok do total += 1
	}

	received = 0
	for received < total {
		_, ok := chan.try_recv(ch)
		if ok do received += 1
	}

	_, _, fdrops_filtered := amps.stats(&h)
	expected_recv := u64(N) / 2
	if u64(received) == expected_recv && fdrops_filtered == expected_recv {
		fmt.printf("PASS filter: %d sent, %d received, %d filter drops\n", total, received, fdrops_filtered)
	} else {
		fmt.printf("FAIL filter: got %d received, %d fdrops, want %d recv + %d drops\n", received, fdrops_filtered, expected_recv, expected_recv)
	}
}

main :: proc() {
	test_exact_routing()
	test_wildcard_routing()
	test_non_match()
	test_filter_routing()
	test_replay_buffer()
	test_10k_roundtrip()
	test_perf()
	test_filter_benefit()
	fmt.println("done")
}
