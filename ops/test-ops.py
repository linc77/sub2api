#!/usr/bin/env python3
"""Exercise operational scripts with fake commands, never the live deployment."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


OPS_DIR = Path(__file__).resolve().parent
CONTAINERS = ["sub2api-postgres", "sub2api-redis", "sub2api"]
LOCAL_URL = "http://127.0.0.1:8081/health"
PUBLIC_URL = "https://77code.cc/health"

FAKE_COMMAND = r'''
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["MOCK_DIR"])
config = json.loads((root / "config.json").read_text())
tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps([tool, *args]) + "\n")

if tool == "curl":
    sys.exit(22 if args[-1] in config.get("failed_urls", []) else 0)
if args[0] == "info":
    sys.exit(0 if config.get("docker_available", True) else 1)
if args[0] == "inspect":
    state = config["states"].get(args[-1])
    if state is None:
        sys.exit(1)
    print(state)
elif args[0] == "ps":
    print("NAMES IMAGE STATUS PORTS")
elif args[0] == "start":
    name = args[-1]
    config["states"][name] = config.get("start_state", "healthy")
    (root / "config.json").write_text(json.dumps(config))
    print(name)
else:
    raise SystemExit("Unexpected Docker operation: " + repr(args))
'''


class OpsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="77code ops ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / "project with spaces" / "ops"
        self.scripts.mkdir(parents=True)
        for source in OPS_DIR.glob("*.sh"):
            shutil.copy2(source, self.scripts / source.name)
        commands = self.root / "fake commands"
        commands.mkdir()
        for name in ("docker", "curl"):
            command = commands / name
            command.write_text(f"#!{sys.executable}\n" + FAKE_COMMAND)
            command.chmod(0o755)
        self.env = {
            **os.environ,
            "DOCKER": str(commands / "docker"),
            "CURL": str(commands / "curl"),
            "MOCK_DIR": str(self.root),
            "APP_CONTAINER": "sub2api",
            "POSTGRES_CONTAINER": "sub2api-postgres",
            "REDIS_CONTAINER": "sub2api-redis",
            "LOCAL_HEALTH_URL": LOCAL_URL,
            "PUBLIC_HEALTH_URL": PUBLIC_URL,
            "START_WAIT_SECONDS": "0",
            "HEALTH_TIMEOUT": "1",
        }
        self.configure()

    def configure(self, **overrides):
        config = {"states": dict.fromkeys(CONTAINERS, "healthy"), **overrides}
        (self.root / "config.json").write_text(json.dumps(config))

    def run_script(self, name):
        return subprocess.run(
            ["sh", str(self.scripts / name)],
            cwd=self.root,
            env=self.env,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def calls(self):
        log = self.root / "calls.jsonl"
        return [json.loads(line) for line in log.read_text().splitlines()]

    def assert_read_only(self):
        for call in self.calls():
            self.assertTrue(
                call[0] == "curl" or call[1] in ("info", "inspect", "ps"), call
            )

    def test_shell_syntax(self):
        for script in self.scripts.glob("*.sh"):
            subprocess.run(["sh", "-n", str(script)], check=True)

    def test_status_from_unrelated_directory_checks_all_containers_and_endpoints(self):
        result = self.run_script("status-77code.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        ps = next(call for call in calls if call[:2] == ["docker", "ps"])
        for name in CONTAINERS:
            self.assertIn(f"name=^/{name}$", ps)
            self.assertIn(f"{name}: healthy", result.stdout)
        self.assertEqual([c[-1] for c in calls if c[0] == "curl"], [LOCAL_URL, PUBLIC_URL])
        self.assert_read_only()

    def test_http_failure_reports_nonzero_and_still_checks_both_endpoints(self):
        self.configure(failed_urls=[LOCAL_URL])
        result = self.run_script("healthcheck-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Local health: failed", result.stderr)
        self.assertIn("Public health: ok", result.stdout)
        self.assert_read_only()

    def test_status_propagates_public_failure(self):
        self.configure(failed_urls=[PUBLIC_URL])
        result = self.run_script("status-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Public health: failed", result.stderr)
        self.assert_read_only()

    def test_docker_unavailable_does_not_attempt_recovery(self):
        self.configure(docker_available=False)
        result = self.run_script("healthcheck-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Docker is unavailable", result.stderr)
        self.assert_read_only()

    def test_unhealthy_container_is_reported_without_restart(self):
        self.configure(states={**dict.fromkeys(CONTAINERS, "healthy"), "sub2api": "unhealthy"})
        result = self.run_script("healthcheck-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("sub2api: unhealthy", result.stdout)
        self.assert_read_only()

    def test_start_leaves_running_containers_untouched(self):
        result = self.run_script("start-77code.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_read_only()

    def test_start_only_starts_existing_containers_in_dependency_order(self):
        self.configure(states=dict.fromkeys(CONTAINERS, "exited"))
        result = self.run_script("start-77code.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        starts = [c[-1] for c in self.calls() if c[:2] == ["docker", "start"]]
        self.assertEqual(starts, CONTAINERS)
        self.assertTrue(all(c[0] == "curl" or c[1] in ("info", "inspect", "start") for c in self.calls()))

    def test_missing_application_prevents_starting_any_dependencies(self):
        self.configure(states=dict.fromkeys(CONTAINERS[:2], "exited"))
        result = self.run_script("start-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("sub2api is missing", result.stderr)
        self.assert_read_only()

    def test_dependency_failure_prevents_starting_application(self):
        self.configure(states=dict.fromkeys(CONTAINERS, "exited"), start_state="unhealthy")
        result = self.run_script("start-77code.sh")
        self.assertEqual(result.returncode, 1)
        starts = [c[-1] for c in self.calls() if c[:2] == ["docker", "start"]]
        self.assertEqual(starts, ["sub2api-postgres"])

    def test_dependency_health_wait_is_bounded(self):
        self.configure(states=dict.fromkeys(CONTAINERS, "exited"), start_state="starting")
        result = self.run_script("start-77code.sh")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Timed out waiting for sub2api-postgres", result.stderr)
        starts = [c[-1] for c in self.calls() if c[:2] == ["docker", "start"]]
        self.assertEqual(starts, ["sub2api-postgres"])


if __name__ == "__main__":
    unittest.main()
