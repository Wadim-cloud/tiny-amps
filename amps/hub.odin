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

filter_match :: proc(filter: string, msg: Message) -> bool {
    f := strings.trim_space(filter)
    if f == "" do return true

    if strings.has_prefix(f, "AND(") && strings.has_suffix(f, ")") {
        inner := f[4:len(f)-1]
        parts := split_filter_clauses(inner)
        for p in parts {
            if !filter_match(p, msg) do return false
        }
        return true
    }
    if strings.has_prefix(f, "OR(") && strings.has_suffix(f, ")") {
        inner := f[3:len(f)-1]
        parts := split_filter_clauses(inner)
        for p in parts {
            if filter_match(p, msg) do return true
        }
        return false
    }
    if strings.has_prefix(f, "NOT(") && strings.has_suffix(f, ")") {
        inner := f[4:len(f)-1]
        return !filter_match(inner, msg)
    }

    if strings.has_prefix(f, "topic = ") {
        topic := f[len("topic = "):]
        if strings.has_prefix(topic, "\"") && strings.has_suffix(topic, "\"") {
            topic = topic[1:len(topic)-1]
        }
        return msg.topic == topic
    }
    if strings.has_prefix(f, "topic != ") {
        topic := f[len("topic != "):]
        if strings.has_prefix(topic, "\"") && strings.has_suffix(topic, "\"") {
            topic = topic[1:len(topic)-1]
        }
        return msg.topic != topic
    }

    seps := []string{" = ", " != ", " > ", " < ", " >= ", " <= "}
    for i := 0; i < len(seps); i += 1 {
        sep := seps[i]
        idx := strings.index(f, sep)
        if idx < 0 do continue
        field := strings.trim_space(f[:idx])
        raw := strings.trim_space(f[idx+len(sep):])
        if field == "topic" {
            val := raw
            if strings.has_prefix(val, "\"") && strings.has_suffix(val, "\"") {
                val = val[1:len(val)-1]
            }
            switch sep {
            case " = ": return msg.topic == val
            case " != ": return msg.topic != val
            }
            continue
        }

        msg_val := parse_body_number(msg.body, field)
        target := parse_number(raw)
        switch sep {
        case " = ": return msg_val == target
        case " != ": return msg_val != target
        case " > ": return msg_val > target
        case " < ": return msg_val < target
        case " >= ": return msg_val >= target
        case " <= ": return msg_val <= target
        }
    }

    if f != "" {
        msg_str := string(msg.body)
        return strings.contains(msg_str, f)
    }
    return true
}

parse_body_number :: proc(body: []byte, field: string) -> f64 {
    if len(body) == 0 do return 0
    text := string(body)
    parts, _ := strings.split(text, " ")
    for part in parts {
        kv, _ := strings.split(part, "=")
        if len(kv) == 2 && strings.trim_space(kv[0]) == field {
            v := strings.trim_space(kv[1])
            n := 0.0
            sign := 1.0
            i := 0
            if i < len(v) && v[i] == '-' {
                sign = -1
                i += 1
            }
            for i < len(v) {
                c := v[i]
                if c >= '0' && c <= '9' {
                    n = n * 10 + f64(c - '0')
                } else if c == '.' {
                    j := i + 1
                    frac := 0.1
                    for j < len(v) && v[j] >= '0' && v[j] <= '9' {
                        n += f64(v[j] - '0') * frac
                        frac *= 0.1
                        j += 1
                    }
                    i = j
                    break
                } else {
                    return 0
                }
                i += 1
            }
            return n * sign
        }
    }
    return 0
}

parse_number :: proc(s: string) -> f64 {
    n := 0.0
    sign := 1.0
    i := 0
    if i < len(s) && s[i] == '-' {
        sign = -1
        i += 1
    }
    for i < len(s) {
        c := s[i]
        if c >= '0' && c <= '9' {
            n = n * 10 + f64(c - '0')
        } else if c == '.' {
            j := i + 1
            frac := 0.1
            for j < len(s) && s[j] >= '0' && s[j] <= '9' {
                n += f64(s[j] - '0') * frac
                frac *= 0.1
                j += 1
            }
            i = j
            break
        } else {
            return 0
        }
        i += 1
    }
    return n * sign
}

split_filter_clauses :: proc(filter: string) -> [dynamic]string {
    out := make([dynamic]string, 0, 4)
    depth := 0
    start := 0
    for i := 0; i < len(filter); i += 1 {
        c := filter[i]
        if c == '(' {
            depth += 1
        } else if c == ')' {
            if depth > 0 do depth -= 1
        } else if c == ',' && depth == 0 {
            clause := strings.trim_space(filter[start:i])
            if clause != "" do append(&out, clause)
            start = i + 1
        }
    }
    clause := strings.trim_space(filter[start:])
    if clause != "" do append(&out, clause)
    return out
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
    replay:      [dynamic]Message,
    replay_lock: sync.Mutex,
    replay_max:  int,
    filter_drop: u64,
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
    h.replay = make([dynamic]Message, 0, 1024)
    h.replay_max = 1000
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
    clear(&h.replay)
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
    if !h.running do return chan.Chan(Message){}, 0

    c, err := chan.create(chan.Chan(Message), buf_size, allocator)
    if err != .None do return chan.Chan(Message){}, 0

    sub := new(Subscription)
    sub.id = h.next_id
    sub.topic = topic
    sub.filter = filter
    sub.ch = c
    sub.active = true

    sync.mutex_lock(&h.mu)
    if len(h.subs) >= MAX_SUBSCRIBERS {
        sync.mutex_unlock(&h.mu)
        return chan.Chan(Message){}, 0
    }
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
    
    sub_id := sub.id
    h.next_id += 1
    sync.mutex_unlock(&h.mu)
    
    // Replay recent messages to new subscriber
    if len(h.replay) > 0 {
        sync.mutex_lock(&h.replay_lock)
        count := len(h.replay)
        if count > 100 { count = 100 }
        for i := len(h.replay) - count; i < len(h.replay); i += 1 {
            if i >= 0 && i < len(h.replay) {
                _ = chan.try_send(c, h.replay[i])
            }
        }
        sync.mutex_unlock(&h.replay_lock)
    }
    
    return c, sub_id
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

        // Add to replay buffer
        sync.mutex_lock(&h.replay_lock)
        if len(h.replay) >= h.replay_max {
            // Remove oldest by rebuilding without first element
            old := h.replay
            h.replay = make([dynamic]Message, 0, cap(old))
            for i := 1; i < len(old); i += 1 {
                append(&h.replay, old[i])
            }
            delete(old)
        }
        append(&h.replay, msg)
        sync.mutex_unlock(&h.replay_lock)

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

            if sub_ptr.filter != "" {
                if !filter_match(sub_ptr.filter, msg) {
                    h.filter_drop += 1
                    continue
                }
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

stats :: proc(h: ^Hub) -> (msgs, drops, fdrops: u64) {
    sync.mutex_lock(&h.mu)
    defer sync.mutex_unlock(&h.mu)
    return h.msg_count, h.drop_count, h.filter_drop
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
