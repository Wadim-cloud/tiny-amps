package amps

import "core:strings"
import "core:fmt"
import "core:time"
import "core:mem"
import "core:slice"
import "core:os"
import "core:net"
import "core:thread"
import "core:sync"
import "core:sync/chan"

MAX_SUBSCRIBERS :: 4096
MAX_TOPIC_LEN   :: 256
MAX_BODY_LEN    :: (64 * 1024)
TOPIC_WILDCARD  :: "*"

Topic :: string

Message :: struct {
    topic: string,
    body: []byte,
}

Subscription :: struct {
    id:      u32,
    topic:   string,
    filter:  string,
    ch:      chan.Chan(Message),
    active:  bool,
}

Subscriber_ID :: u32

Hub :: struct {
    subs:        map[Subscriber_ID]^Subscription,
    topic_index: map[string][dynamic]u32,
    wc_index:    map[string][dynamic]u32,
    mu:          sync.Mutex,
    next_id:     u32,
    msg_count:   u64,
    drop_count:  u64,
    input_ch:    chan.Chan(Message),
    running:     bool,
}

topic_matcher :: proc(t, p: string) -> bool {
    if p == "*" do return true
    if strings.has_prefix(p, "*") && strings.has_suffix(p, "*") {
        return strings.contains(t, p[1:len(p)-1])
    }
    if strings.has_prefix(p, "*") {
        return strings.has_suffix(t, p[1:])
    }
    if strings.has_suffix(p, "*") {
        return strings.has_prefix(t, p[:len(p)-1])
    }
    return t == p
}

remove_u32 :: proc(s: [dynamic]u32, v: u32) -> (out: [dynamic]u32) {
    out = make([dynamic]u32, 0, len(s))
    for x in s {
        if x != v do append(&out, x)
    }
    return
}

hub_init :: proc(allocator := context.allocator) -> (h: Hub) {
    h.subs = make(map[Subscriber_ID]^Subscription, 256)
    h.topic_index = make(map[string][dynamic]u32, 256)
    h.wc_index = make(map[string][dynamic]u32, 64)
    h.next_id = 1
    c, _ := chan.create(chan.Chan(Message), 65536, allocator)
    h.input_ch = c
    h.running = true
    return
}

hub_destroy :: proc(h: ^Hub, allocator := context.allocator) {
    h.running = false
    sync.mutex_lock(&h.mu)
    defer sync.mutex_unlock(&h.mu)

    for id, sub_ptr in h.subs {
        if sub_ptr != nil && sub_ptr.active {
            sub_ptr.active = false
            chan.close(sub_ptr.ch)
        }
        delete_key(&h.subs, id)
    }
    for k, _ in h.topic_index { delete_key(&h.topic_index, k) }
    for k, _ in h.wc_index { delete_key(&h.wc_index, k) }
}

publish :: proc(h: ^Hub, msg: Message) -> bool {
    if !h.running do return false
    ok := chan.send(h.input_ch, msg)
    if ok { h.msg_count += 1 }
    return ok
}

subscribe :: proc(
    h: ^Hub,
    topic: string,
    filter: string,
    buf_size: int,
    allocator := context.allocator,
) -> (chan.Chan(Message), u32) {
    if !h.running do return nil, 0

    c, err := chan.create(chan.Chan(Message), buf_size, allocator)
    if err != .None do return nil, 0

    sub := new(Subscription)
    sub.id = h.next_id
    sub.topic = topic
    sub.filter = filter
    sub.ch = c
    sub.active = true

    sync.mutex_lock(&h.mu)
    defer sync.mutex_unlock(&h.mu)
    if len(h.subs) >= MAX_SUBSCRIBERS do return nil, 0

    h.subs[sub.id] = sub

    if strings.contains(topic, TOPIC_WILDCARD) {
        parts, _ := strings.split(topic, TOPIC_WILDCARD, allocator)
        prefix := parts[0]
        wlist := h.wc_index[prefix]
        append(&wlist, sub.id)
        h.wc_index[prefix] = wlist
    } else {
        elist := h.topic_index[topic]
        append(&elist, sub.id)
        h.topic_index[topic] = elist
    }
    h.next_id += 1
    return c, sub.id
}

unsubscribe :: proc(h: ^Hub, id: u32) {
    sync.mutex_lock(&h.mu)
    defer sync.mutex_unlock(&h.mu)

    sub_ptr, found := h.subs[id]
    if !found || sub_ptr == nil || !sub_ptr.active do return
    sub_ptr.active = false
    chan.close(sub_ptr.ch)

    if list, found := h.topic_index[sub_ptr.topic]; found {
        new_list := remove_u32(list, id)
        if len(new_list) > 0 {
            h.topic_index[sub_ptr.topic] = new_list
        } else {
            delete_key(&h.topic_index, sub_ptr.topic)
        }
    }

    for prefix, list in h.wc_index {
        new_list := remove_u32(list, id)
        if len(new_list) > 0 {
            h.wc_index[prefix] = new_list
        } else {
            delete_key(&h.wc_index, prefix)
        }
    }
    delete_key(&h.subs, id)
}

dispatch_loop :: proc(h: ^Hub) {
    for {
        msg, ok := chan.recv(h.input_ch)
        if !ok || !h.running do break

        sync.mutex_lock(&h.mu)
        defer sync.mutex_unlock(&h.mu)

        matching := make([dynamic]u32, 0, 16)
        defer clear(&matching)

        if ids, found := h.topic_index[msg.topic]; found {
            for id in ids do append(&matching, id)
        }
        for prefix, ids in h.wc_index {
            if strings.has_prefix(msg.topic, prefix) {
                for id in ids do append(&matching, id)
            }
        }

        delivered := make(map[u32]bool, 0)
        defer delete(delivered)
        for id in matching {
            if delivered[id] do continue
            delivered[id] = true
            sub_ptr, found := h.subs[id]
            if !found || sub_ptr == nil || !sub_ptr.active do continue

            // Filter check (Sprint 2 placeholder)
            if sub_ptr.filter != "" {
                if false do continue  // TODO: filter_match(sub_ptr.filter, msg)
            }

            ok := chan.try_send(sub_ptr.ch, msg)
            if !ok { h.drop_count += 1 }
        }
    }
}

start_dispatch :: proc(h: ^Hub) {
    thread.run_with_data(rawptr(h), proc(data: rawptr) {
        dispatch_loop(cast(^Hub)data)
    })
}

stats :: proc(h: ^Hub) -> (msgs, drops: u64) {
    sync.mutex_lock(&h.mu)
    defer sync.mutex_unlock(&h.mu)
    return h.msg_count, h.drop_count
}

serve_tcp :: proc(h: ^Hub, port: int) {
    ep := net.Endpoint{net.IP4_Address{127, 0, 0, 1}, port}
    listener, err := net.listen_tcp(ep)
    if err != nil {
        fmt.eprintf("listen failed: %v\n", err)
        return
    }
    fmt.printf("amps hub :%d\n", port)

    handle_conn :: proc(sock: net.TCP_Socket) {
        header := make([]u8, 6)
        for {
            _, ok := recv_all(sock, 6)
            if !ok do break
            topic_len := (u16(header[0]) << 8) | u16(header[1])
            body_len := (u32(header[2]) << 24) | (u32(header[3]) << 16) |
                        (u32(header[4]) << 8) | u32(header[5])
            if topic_len == 0 || body_len > MAX_BODY_LEN do break

            topic_bytes, ok1 := recv_all(sock, int(topic_len))
            body_bytes, ok2 := recv_all(sock, int(body_len))
            if !ok1 || !ok2 do break

            _ = topic_bytes
            _ = body_bytes
        }
        net.close(sock)
    }

    for {
        conn, _, aerr := net.accept_tcp(listener)
        if aerr != nil {
            continue
        }
        thread.run_with_data(rawptr(uintptr(conn)), proc(data: rawptr) {
            handle_conn(cast(net.TCP_Socket)(uintptr(data)))
        })
    }
}

recv_all :: proc(sock: net.TCP_Socket, n: int) -> (buf: []u8, ok: bool) {
    buf = make([]u8, n)
    total := 0
    for total < n {
        m := n - total
        if m > 4096 do m = 4096
        br, _ := net.recv(sock, buf[total:total+m])
        if br <= 0 do return buf, false
        total += br
    }
    return buf, true
}
