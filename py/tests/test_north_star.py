import time
import resource
import zmq
import sys

sys.path.insert(0, "/home/ds/dev/tiny-amps/py")
from amps import TinyAMPS

NUM_AGENTS = 80
PUBLISH_ROUNDS = 50
TOTAL_MSGS = NUM_AGENTS * PUBLISH_ROUNDS  # 4000


def cpu_time():
    r = resource.getrusage(resource.RUSAGE_SELF)
    return r.ru_utime + r.ru_stime


def simulate_brain_work(msg_count):
    """Realistic swarmsim brain: parse topics, update state, check thresholds."""
    state = {}
    history = []
    alerts = []
    
    cpu_start = cpu_time()
    for idx in range(msg_count):
        agent_id = idx % NUM_AGENTS
        value = (agent_id + (idx // NUM_AGENTS)) % 256
        
        state[agent_id] = {
            'last_seen': time.time(),
            'value': value,
        }
        
        if value > 20:
            alerts.append(agent_id)
        
        history.append((agent_id, value))
    
    cpu_end = cpu_time()
    return cpu_end - cpu_start, len(alerts), len(history)


def run_odin_filtered():
    client = TinyAMPS()
    try:
        sub_id = client.subscribe("agent.*", filter_text='topic = "agent.0"', buf_size=TOTAL_MSGS)
        time.sleep(0.1)
        
        for r in range(PUBLISH_ROUNDS):
            for i in range(NUM_AGENTS):
                client.publish(f"agent.{i}", bytes([i, i >> 8]))
        
        time.sleep(0.3)
        
        msgs, drops, fdrops = client.stats()
        recv = msgs - drops - fdrops
        brain_cpu, alerts, history_len = simulate_brain_work(recv)
        
        return {
            "backend": "odin+filter",
            "sent": TOTAL_MSGS,
            "recv": recv,
            "drops": drops + fdrops,
            "brain_cpu_s": brain_cpu,
            "cpu_per_1k": (brain_cpu / max(1, recv)) * 1000,
            "alerts": alerts,
            "history": history_len,
        }
    finally:
        client.unsubscribe(sub_id)
        client.close()


def run_zmq_unfiltered():
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.bind("tcp://127.0.0.1:5562")
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://127.0.0.1:5562")
    sub.setsockopt(zmq.SUBSCRIBE, b"agent.")
    time.sleep(0.1)
    
    for r in range(PUBLISH_ROUNDS):
        for i in range(NUM_AGENTS):
            pub.send_multipart([f"agent.{i}".encode(), bytes([i, i >> 8])])
    
    time.sleep(0.3)
    
    recv = 0
    try:
        while True:
            sub.recv_multipart(flags=zmq.NOBLOCK)
            recv += 1
    except zmq.Again:
        pass
    
    brain_cpu, alerts, history_len = simulate_brain_work(recv)
    
    pub.close()
    sub.close()
    ctx.term()
    
    return {
        "backend": "zmq+no-filter",
        "sent": TOTAL_MSGS,
        "recv": recv,
        "drops": 0,
        "brain_cpu_s": brain_cpu,
        "cpu_per_1k": (brain_cpu / max(1, recv)) * 1000,
        "alerts": alerts,
        "history": history_len,
    }


def run_zmq_python_filter():
    ctx = zmq.Context()
    pub = ctx.socket(zmq.PUB)
    pub.bind("tcp://127.0.0.1:5563")
    sub = ctx.socket(zmq.SUB)
    sub.connect("tcp://127.0.0.1:5563")
    sub.setsockopt(zmq.SUBSCRIBE, b"agent.0")
    time.sleep(0.1)
    
    for r in range(PUBLISH_ROUNDS):
        for i in range(NUM_AGENTS):
            pub.send_multipart([f"agent.{i}".encode(), bytes([i, i >> 8])])
    
    time.sleep(0.3)
    
    recv = 0
    try:
        while True:
            msg = sub.recv_multipart(flags=zmq.NOBLOCK)
            recv += 1
    except zmq.Again:
        pass
    
    brain_cpu, alerts, history_len = simulate_brain_work(recv)
    
    pub.close()
    sub.close()
    ctx.term()
    
    return {
        "backend": "zmq+python-filter",
        "sent": TOTAL_MSGS,
        "recv": recv,
        "drops": TOTAL_MSGS - recv,
        "brain_cpu_s": brain_cpu,
        "cpu_per_1k": (brain_cpu / max(1, recv)) * 1000,
        "alerts": alerts,
        "history": history_len,
    }


if __name__ == "__main__":
    print("backend,sent,recv,drops,brain_cpu_s,cpu_per_1k,alerts,history")
    for fn in [run_odin_filtered, run_zmq_unfiltered, run_zmq_python_filter]:
        result = fn()
        print(f"{result['backend']},{result['sent']},{result['recv']},{result['drops']},{result['brain_cpu_s']:.6f},{result['cpu_per_1k']:.6f},{result['alerts']},{result['history']}")
