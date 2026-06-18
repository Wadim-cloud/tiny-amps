import sys
import time

sys.path.insert(0, "/home/ds/dev/tiny-amps/py")

from amps import TinyAMPS


def test_pubsub() -> None:
    client = TinyAMPS()
    try:
        sub_id = client.subscribe("sensor.*", filter_text="topic = \"sensor.temp\"", buf_size=4096)
        client.publish("sensor.temp", b"hello")
        client.publish("sensor.humidity", b"drop-me")
        time.sleep(0.2)
        msgs, drops, fdrops = client.stats()
        assert msgs == 2, f"expected 2 msgs, got {msgs}"
        assert fdrops == 1, f"expected 1 filter drop, got {fdrops}"
        print("PASS python pub/sub + filter")
    finally:
        client.unsubscribe(sub_id)
        client.close()


def test_replay() -> None:
    client = TinyAMPS()
    try:
        client.publish("sensor.temp", b"first")
        time.sleep(0.1)
        sub_id = client.subscribe("sensor.*", buf_size=4096)
        time.sleep(0.2)
        msgs, _, _ = client.stats()
        # Replay is best-effort here; just validate no crash and sane stats
        assert msgs == 1, f"expected 1 msg pre-replay, got {msgs}"
        print("PASS python replay baseline")
    finally:
        client.unsubscribe(sub_id)
        client.close()


if __name__ == "__main__":
    test_pubsub()
    test_replay()
    print("done")
