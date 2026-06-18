import time
import zmq
import os
import sys

sys.path.insert(0, "/home/ds/dev/tiny-amps/py")
from amps import TinyAMPS

NUM_AGENTS = 80


def run_odin(rounds):
    client = TinyAMPS()
    try:
        sub_id = client.subscribe("agent.*", buf_size=NUM_AGENTS * rounds)
        time.sleep(0.05)
        start = time.perf_counter()
        sent = 0
        for _ in range(rounds):
            for i in range(NUM_AGENTS):
                body = bytes([i, i >> 8])
                if client.publish(f"agent.{i}", body):
                    sent += 1
        time.sleep(0.3)
        msgs, drops, fdrops = client.stats()
        elapsed = time.perf_counter() - start
        return sent, msgs - drops - fdrops, elapsed, fdrops
    finally:
        client.unsubscribe(sub_id)
        client.close()


def run_zmq(rounds):
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.bind("tcp://127.0.0.1:5560")
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://127.0.0.1:5560")
    sub.setsockopt(zmq.SUBSCRIBE, b"agent.")
    time.sleep(0.1)
    start = time.perf_counter()
    sent = 0
    for _ in range(rounds):
        for i in range(NUM_AGENTS):
            pub.send_multipart([f"agent.{i}".encode(), bytes([i, i >> 8])])
            sent += 1
    time.sleep(0.3)
    recv = 0
    try:
        while True:
            sub.recv_multipart(flags=zmq.NOBLOCK)
            recv += 1
    except zmq.Again:
        pass
    elapsed = time.perf_counter() - start
    return sent, recv, elapsed, 0


if __name__ == "__main__":
    print("load,backend,sent,recv,elapsed_s,throughput,fdrops")
    for rounds in [10, 50, 200]:
        for label, fn in [("odin", run_odin), ("zmq", run_zmq)]:
            sent, recv, elapsed, fdrops = fn(rounds)
            throughput = recv / elapsed if elapsed > 0 else 0
            print(f"{rounds},{label},{sent},{recv},{elapsed:.3f},{throughput:.1f},{fdrops}")
