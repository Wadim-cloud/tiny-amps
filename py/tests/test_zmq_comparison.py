import time
import zmq
import os

NUM_AGENTS = 80
PUBLISH_ROUNDS = 50


def test_zmq_pubsub():
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.bind("tcp://127.0.0.1:5555")
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://127.0.0.1:5555")
    sub.setsockopt(zmq.SUBSCRIBE, b"agent.")

    time.sleep(0.1)
    start = time.perf_counter()
    total_sent = 0
    total_recv = 0
    for _ in range(PUBLISH_ROUNDS):
        for i in range(NUM_AGENTS):
            topic = f"agent.{i}".encode("utf-8")
            body = bytes([i, i >> 8])
            pub.send_multipart([topic, body])
            total_sent += 1

    time.sleep(0.2)

    for _ in range(total_sent):
        sub.recv_multipart()
        total_recv += 1

    elapsed = time.perf_counter() - start
    throughtput = total_recv / elapsed if elapsed > 0 else 0.0
    print(f"PASS zmq: {NUM_AGENTS} agents, {PUBLISH_ROUNDS} rounds, {total_sent} sent, {total_recv} recv, {elapsed:.3f}s, {throughtput:.2f} msg/s")

    pub.close()
    sub.close()
    ctx.term()


if __name__ == "__main__":
    test_zmq_pubsub()
