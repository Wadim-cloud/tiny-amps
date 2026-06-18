package amps

import "core:c"
import "core:strings"
import "core:sync"
import "core:sync/chan"
import "core:thread"

amps_init :: proc() -> rawptr {
    h := new(Hub)
    h^ = hub_init()
    start_dispatch(h)
    return rawptr(h)
}

amps_close :: proc(h: rawptr) {
    if h == nil do return
    hub_destroy(cast(^Hub)h)
}

amps_publish :: proc(h: rawptr, topic: cstring, body: []u8) -> bool {
    if h == nil || topic == nil do return false
    return publish(cast(^Hub)h, Message{topic = string(topic), body = body})
}

amps_subscribe :: proc(h: rawptr, topic: cstring, filter: cstring, buf_size: int) -> u32 {
    if h == nil || topic == nil do return 0
    _, id := subscribe(cast(^Hub)h, string(topic), string(filter), buf_size)
    return id
}

amps_unsubscribe :: proc(h: rawptr, id: u32) {
    if h == nil do return
    unsubscribe(cast(^Hub)h, id)
}

amps_stats :: proc(h: rawptr, msgs: ^u64, drops: ^u64, fdrops: ^u64) {
    if h == nil do return
    m, d, f := stats(cast(^Hub)h)
    if msgs != nil { msgs^ = m }
    if drops != nil { drops^ = d }
    if fdrops != nil { fdrops^ = f }
}
