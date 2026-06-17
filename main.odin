package main

import "core:fmt"
import "core:time"
import "core:sync/chan"
import "amps"

test_exact_routing :: proc() {
    h := amps.hub_init()
    defer amps.hub_destroy(&h)
    amps.start_dispatch(&h)

    ch, _ := amps.subscribe(&h, "sensor.temp", buf_size=8)
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

    ch, _ := amps.subscribe(&h, "sensor.*", buf_size=8)
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

    ch, _ := amps.subscribe(&h, "other.*", buf_size=8)
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

main :: proc() {
    test_exact_routing()
    test_wildcard_routing()
    test_non_match()
    fmt.println("done")
}
