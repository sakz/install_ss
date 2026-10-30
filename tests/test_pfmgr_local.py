from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "pfmgr-v2.2.0.sh"


class LocalForwardTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.functions = self.root / "functions.sh"
        self.functions.write_text(SCRIPT.read_text().rsplit('\nmain "$@"', 1)[0])
        self.db = self.root / "rules.tsv"
        self.db.write_text("")

    def run_commands(self, commands):
        return subprocess.run(
            ["bash", "-c", r'''
source "$1"
BASE_DIR="$2"
DB="${BASE_DIR}/rules.tsv"
ensure_dirs() { :; }
prepare_write() { :; }
apply_rules() {
    render_runtime_nft "${BASE_DIR}/runtime.nft"
    render_persistent_nft "${BASE_DIR}/persistent.nft"
}
eval "$3"
''', "pfmgr-test", str(self.functions), str(self.root), commands],
            text=True, capture_output=True,
        )

    def assert_success(self, commands):
        result = self.run_commands(commands)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_local_add_and_list(self):
        output = self.assert_success("cmd_add 8090 local 8080; cmd_list")
        self.assertEqual(self.db.read_text(), "8090\tlocal\t8080\n")
        self.assertIn("local", output)
        self.assertIn("8080", output)

    def test_local_and_remote_rule_generation(self):
        self.assert_success("cmd_add 8090 local 8080; cmd_add 8443 192.0.2.10 443")
        for name in ("runtime.nft", "persistent.nft"):
            rules = (self.root / name).read_text()
            for protocol in ("tcp", "udp"):
                self.assertEqual(rules.count(
                    f"fib daddr type local {protocol} dport 8090 dnat to :8080"
                ), 2, rules)
                self.assertIn(f"{protocol} dport 8443 dnat to 192.0.2.10:443", rules)
                self.assertIn(f"pfmgr {protocol} masq 8443", rules)
                self.assertNotIn(f"pfmgr {protocol} masq 8090", rules)
                self.assertEqual(rules.count(f'comment "pfmgr-stat up {protocol} 8090"'), 1)
                self.assertEqual(rules.count(f'comment "pfmgr-stat down {protocol} 8090"'), 1)
            self.assertNotIn("ip daddr local", rules)
            self.assertIn("ct direction original ct status dnat", rules)
            self.assertIn("ct direction reply ct status dnat", rules)

    def test_update_between_local_and_remote(self):
        self.assert_success("cmd_add 8090 192.0.2.10 80; cmd_update 8090 local 8080")
        self.assertEqual(self.db.read_text(), "8090\tlocal\t8080\n")
        self.assert_success("cmd_update 8090 192.0.2.20 443")
        self.assertEqual(self.db.read_text(), "8090\t192.0.2.20\t443\n")
        self.assertNotIn("dnat to :8080", (self.root / "runtime.nft").read_text())

    def test_delete_and_clear_local_rules(self):
        self.assert_success("cmd_add 8090 local 8080; cmd_delete 8090")
        self.assertEqual(self.db.read_text(), "")
        self.assertNotIn("dnat to :8080", (self.root / "runtime.nft").read_text())
        self.assert_success("cmd_add 8090 local 8080; cmd_clear")
        self.assertEqual(self.db.read_text(), "")

    def test_invalid_local_rules_do_not_change_database(self):
        for arguments in ("8090 local 8090", "8090 local", "0 local 8080",
                          "8090 local 65536", "8090 invalid 8080"):
            with self.subTest(arguments=arguments):
                result = self.run_commands(f"cmd_add {arguments}")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.db.read_text(), "")

    def test_duplicate_listen_port_is_rejected(self):
        self.assert_success("cmd_add 8090 local 8080")
        result = self.run_commands("cmd_add 8090 local 8081")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.db.read_text(), "8090\tlocal\t8080\n")

    def test_invalid_local_update_preserves_existing_rule(self):
        self.assert_success("cmd_add 8090 192.0.2.10 443")
        result = self.run_commands("cmd_update 8090 local 8090")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.db.read_text(), "8090\t192.0.2.10\t443\n")

    def test_failed_apply_restores_previous_database(self):
        self.assert_success("cmd_add 8090 local 8080")
        result = self.run_commands("apply_rules() { return 1; }; cmd_update 8090 local 8081")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.db.read_text(), "8090\tlocal\t8080\n")

    def test_remote_default_port_is_preserved(self):
        self.assert_success("cmd_add 443 192.0.2.10")
        self.assertEqual(self.db.read_text(), "443\t192.0.2.10\t443\n")

    def test_forward_firewall_skips_local_targets(self):
        self.db.write_text("8090\tlocal\t8080\n8443\t192.0.2.10\t443\n")
        output = self.assert_success(r'''
ensure_iptables() { :; }
iptables() {
    case " $* " in
        *" -C "*) return 1 ;;
        *" -nL "*) return 0 ;;
        *) printf '%s\n' "$*" ;;
    esac
}
sync_forward_rules
''')
        self.assertNotIn(" local ", output)
        self.assertNotIn("pfmgr tcp 8090", output)
        self.assertIn("192.0.2.10", output)


if __name__ == "__main__":
    unittest.main()
