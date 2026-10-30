"""Run with PFMGR_INTEGRATION=1 inside a disposable, privileged Linux container.

Requires nftables, iptables, iproute2, procps and Python 3. Tests use a separate network
namespace as an external client/target and never use the host network namespace.
"""

import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TABLE = "pfmgr_test_nat"
NAMESPACE = "pfmgr-test-peer"
SERVER = r'''
import os, socket, sys, threading

def serve(port, protocol):
    kind = socket.SOCK_STREAM if protocol == "tcp" else socket.SOCK_DGRAM
    with socket.socket(socket.AF_INET, kind) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("0.0.0.0", port))
        if protocol == "tcp":
            server.listen()
        os.write(1, b"ready\n")
        while True:
            if protocol == "tcp":
                connection, address = server.accept()
                with connection:
                    payload = connection.recv(4096)
                    connection.sendall(f"{sys.argv[1]}:{port}|{address[0]}|".encode() + payload)
            else:
                payload, address = server.recvfrom(4096)
                server.sendto(f"{sys.argv[1]}:{port}|{address[0]}|".encode() + payload, address)

for port in map(int, sys.argv[2:]):
    for protocol in ("tcp", "udp"):
        threading.Thread(target=serve, args=(port, protocol), daemon=True).start()
threading.Event().wait()
'''
CLIENT = r'''
import socket, sys
kind = socket.SOCK_STREAM if sys.argv[3] == "tcp" else socket.SOCK_DGRAM
with socket.socket(socket.AF_INET, kind) as client:
    client.settimeout(2)
    client.connect((sys.argv[1], int(sys.argv[2])))
    client.sendall(b"pfmgr-payload")
    print(client.recv(4096).decode())
'''


def run(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True).stdout


@unittest.skipUnless(os.environ.get("PFMGR_INTEGRATION") == "1",
                     "requires an explicitly selected disposable Linux container")
class NetworkForwardTests(unittest.TestCase):
    def test_real_network_forwarding(self):
        self.assertTrue(Path("/.dockerenv").exists(), "Run only inside a disposable container")
        with tempfile.TemporaryDirectory() as directory, contextlib.ExitStack() as cleanup:
            work = Path(directory)
            functions = work / "functions.sh"
            functions.write_text((ROOT / "pfmgr-v2.2.0.sh").read_text().rsplit('\nmain "$@"', 1)[0])
            wrapper = work / "pfmgr"
            wrapper.write_text('''#!/usr/bin/env bash
source "$(dirname "$0")/functions.sh"
BASE_DIR="$(dirname "$0")/config"
DB="${BASE_DIR}/rules.tsv"
LOCK_FILE="${BASE_DIR}/lock"
NFT_DIR="$(dirname "$0")/nft"
NFT_FILE="${NFT_DIR}/pfmgr.nft"
TABLE="pfmgr_test_nat"
IPT_CHAIN="PFMGR-TEST"
prepare_write() { ensure_dirs; lock_db; }
main "$@"
''')

            def pfmgr(*arguments):
                return run("bash", str(wrapper), *map(str, arguments))

            run("ip", "netns", "add", NAMESPACE)
            cleanup.callback(subprocess.run, ["ip", "netns", "delete", NAMESPACE], check=False)
            run("ip", "link", "add", "pfmgr-veth", "type", "veth", "peer", "name", "pfmgr-peer")
            cleanup.callback(subprocess.run, ["ip", "link", "delete", "pfmgr-veth"], check=False)
            run("ip", "link", "set", "pfmgr-peer", "netns", NAMESPACE)
            run("ip", "address", "add", "192.0.2.1/24", "dev", "pfmgr-veth")
            run("ip", "link", "set", "pfmgr-veth", "up")
            run("ip", "netns", "exec", NAMESPACE, "ip", "address", "add", "192.0.2.2/24", "dev", "pfmgr-peer")
            run("ip", "netns", "exec", NAMESPACE, "ip", "link", "set", "pfmgr-peer", "up")
            run("ip", "netns", "exec", NAMESPACE, "ip", "link", "set", "lo", "up")
            run("sysctl", "-w", "net.ipv4.ip_forward=1")

            old_policy = run("iptables", "-S", "FORWARD").splitlines()[0].split()[-1]
            run("iptables", "-P", "FORWARD", "DROP")
            cleanup.callback(subprocess.run, ["iptables", "-P", "FORWARD", old_policy], check=False)

            def remove_rules():
                subprocess.run(["nft", "delete", "table", "ip", TABLE], check=False)
                subprocess.run(["iptables", "-D", "FORWARD", "-j", "PFMGR-TEST"], check=False)
                subprocess.run(["iptables", "-F", "PFMGR-TEST"], check=False)
                subprocess.run(["iptables", "-X", "PFMGR-TEST"], check=False)

            cleanup.callback(remove_rules)

            def server(marker, ports, external=False):
                command = [sys.executable, "-u", "-c", SERVER, marker, *map(str, ports)]
                if external:
                    command = ["ip", "netns", "exec", NAMESPACE, *command]
                process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
                cleanup.callback(process.wait, timeout=5)
                cleanup.callback(process.terminate)
                cleanup.callback(process.stdout.close)
                for _ in range(len(ports) * 2):
                    self.assertEqual(process.stdout.readline().strip(), "ready")

            server("local", [8080, 8081])
            server("peer", [8080, 8090], external=True)

            def probe(address, port, protocol, expected, source=None, external=False):
                command = [sys.executable, "-c", CLIENT, address, str(port), protocol]
                if external:
                    command = ["ip", "netns", "exec", NAMESPACE, *command]
                response = run(*command).strip().split("|")
                self.assertEqual(response[0], expected)
                self.assertEqual(response[2], "pfmgr-payload")
                if source is not None:
                    self.assertEqual(response[1], source)

            def counters():
                values = {}
                for entry in json.loads(run("nft", "-j", "list", "table", "ip", TABLE))["nftables"]:
                    rule = entry.get("rule", {})
                    if rule.get("comment", "").startswith("pfmgr-stat"):
                        values[rule["comment"]] = next(
                            expression["counter"]["packets"] for expression in rule["expr"]
                            if "counter" in expression
                        )
                return values

            pfmgr("add", 8090, "local", 8080)
            for _ in range(3):
                probe("127.0.0.1", 8090, "udp", "local:8080", "127.0.0.1")
            initial = counters()
            self.assertEqual(initial["pfmgr-stat up udp 8090"], 3)
            self.assertEqual(initial["pfmgr-stat down udp 8090"], 3)
            print("PASS: loopback UDP packets counted exactly once in each direction", flush=True)

            for protocol in ("tcp", "udp"):
                probe("127.0.0.1", 8090, protocol, "local:8080", "127.0.0.1")
                probe("192.0.2.1", 8090, protocol, "local:8080", "192.0.2.1")
                probe("192.0.2.1", 8090, protocol, "local:8080", "192.0.2.2", external=True)
                probe("192.0.2.2", 8090, protocol, "peer:8090", "192.0.2.1")
            print("PASS: TCP/UDP loopback, local IP, external client and unrelated outgoing traffic", flush=True)

            pfmgr("add", 8443, "192.0.2.2", 8080)
            for protocol in ("tcp", "udp"):
                probe("192.0.2.1", 8443, protocol, "peer:8080", external=True)
                probe("127.0.0.1", 8090, protocol, "local:8080")
            self.assertTrue(all(count > 0 for count in counters().values()))
            stats = pfmgr("stats")
            self.assertIn("local:8080", stats)
            self.assertIn("192.0.2.2:8080", stats)
            print("PASS: existing remote forwarding under FORWARD DROP and mixed stats", flush=True)

            configuration = work / "nft" / "pfmgr.nft"
            runtime = json.loads(run("nft", "-j", "list", "table", "ip", TABLE))
            run("nft", "delete", "table", "ip", TABLE)
            run("nft", "-c", "-f", str(configuration))
            run("nft", "-f", str(configuration))
            restored = json.loads(run("nft", "-j", "list", "table", "ip", TABLE))

            def rule_counts(data):
                return [entry["rule"]["comment"] for entry in data["nftables"] if "rule" in entry]

            self.assertCountEqual(rule_counts(runtime), rule_counts(restored))
            for protocol in ("tcp", "udp"):
                probe("192.0.2.1", 8090, protocol, "local:8080", external=True)
                probe("127.0.0.1", 8090, protocol, "local:8080")
                probe("192.0.2.1", 8443, protocol, "peer:8080", external=True)
            print("PASS: persistent configuration restores local and remote forwarding", flush=True)

            pfmgr("update", 8090, "192.0.2.2", 8080)
            for protocol in ("tcp", "udp"):
                probe("192.0.2.1", 8090, protocol, "peer:8080", external=True)
            pfmgr("update", 8090, "local", 8081)
            for protocol in ("tcp", "udp"):
                probe("127.0.0.1", 8090, protocol, "local:8081")
                probe("192.0.2.1", 8090, protocol, "local:8081", external=True)
            pfmgr("delete", 8090)
            with socket.socket() as connection:
                connection.settimeout(1)
                self.assertNotEqual(connection.connect_ex(("127.0.0.1", 8090)), 0)
            self.assertNotIn("8090", run("nft", "list", "table", "ip", TABLE))
            pfmgr("clear")
            self.assertEqual(counters(), {})
            self.assertEqual((work / "config" / "rules.tsv").read_text(), "")
            print("PASS: local/remote updates, deletion and clear remove the intended rules", flush=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
