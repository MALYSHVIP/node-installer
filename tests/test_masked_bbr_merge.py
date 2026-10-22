#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MERGER = ROOT / "bin" / "remnanode-masked-bbr-merge"


CONTRACT = {
    "schema": "tokervpn-remnawave-masked-bbr/v1",
    "streamSettings": {
        "network": "hysteria",
        "security": "tls",
        "tlsSettings": {"alpn": ["h3"]},
        "hysteriaSettings": {"version": 2, "masquerade": {"type": "string", "content": "cover"}},
        "finalmask": {
            "quicParams": {"congestion": "bbr", "disablePathMTUDiscovery": True},
            "udp": [{"type": "salamander", "settings": {"password": "secret"}}],
        },
    },
}


PROFILE = {
    "name": "profile-a",
    "config": {
        "inbounds": [
            {
                "id": "keep-id",
                "tag": "BBR-IN-443",
                "listen": "0.0.0.0",
                "port": 443,
                "protocol": "hysteria",
                "settings": {"version": 2, "clients": [{"email": "must-stay"}]},
                "streamSettings": {"network": "hysteria", "old": True},
            },
            {"tag": "UNRELATED", "port": 8443, "protocol": "vless", "settings": {"x": 1}},
        ],
        "routing": {"rules": [{"type": "field", "outboundTag": "direct"}]},
    },
}


class MergeTests(unittest.TestCase):
    def run_merge(self, contract: dict = CONTRACT, profile: dict = PROFILE) -> tuple[subprocess.CompletedProcess[str], Path, tempfile.TemporaryDirectory[str]]:
        temp = tempfile.TemporaryDirectory()
        directory = Path(temp.name)
        profile_path = directory / "profile.json"
        contract_path = directory / "contract.json"
        output_path = directory / "candidate.json"
        profile_path.write_text(json.dumps(profile), encoding="utf-8")
        contract_path.write_text(json.dumps(contract), encoding="utf-8")
        result = subprocess.run(
            [str(MERGER), "--profile", str(profile_path), "--contract", str(contract_path),
             "--inbound-tag", "BBR-IN-443", "--output", str(output_path)],
            text=True, capture_output=True, check=False,
        )
        return result, output_path, temp

    def test_merges_only_target_stream_settings(self) -> None:
        result, output, temp = self.run_merge()
        self.addCleanup(temp.cleanup)
        self.assertEqual(result.returncode, 0, result.stderr)
        candidate = json.loads(output.read_text(encoding="utf-8"))
        before = PROFILE["config"]["inbounds"][0]
        after = candidate["config"]["inbounds"][0]
        for key in ("id", "tag", "listen", "port", "protocol", "settings"):
            self.assertEqual(after[key], before[key])
        self.assertEqual(after["streamSettings"], CONTRACT["streamSettings"])
        self.assertEqual(candidate["config"]["inbounds"][1], PROFILE["config"]["inbounds"][1])
        self.assertEqual(candidate["config"]["routing"], PROFILE["config"]["routing"])

    def test_rejects_gecko_packet_size(self) -> None:
        contract = copy.deepcopy(CONTRACT)
        contract["streamSettings"]["finalmask"]["udp"][0]["settings"]["packetSize"] = "512-1200"
        result, output, temp = self.run_merge(contract=contract)
        self.addCleanup(temp.cleanup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GECKO", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_wrong_target(self) -> None:
        profile = copy.deepcopy(PROFILE)
        profile["config"]["inbounds"][0]["protocol"] = "vless"
        result, output, temp = self.run_merge(profile=profile)
        self.addCleanup(temp.cleanup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not Hysteria", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_duplicate_target_tag(self) -> None:
        profile = copy.deepcopy(PROFILE)
        profile["config"]["inbounds"].append(copy.deepcopy(profile["config"]["inbounds"][0]))
        result, output, temp = self.run_merge(profile=profile)
        self.addCleanup(temp.cleanup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("found 2", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_wrong_port(self) -> None:
        profile = copy.deepcopy(PROFILE)
        profile["config"]["inbounds"][0]["port"] = 8443
        result, output, temp = self.run_merge(profile=profile)
        self.addCleanup(temp.cleanup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("port 443", result.stderr)
        self.assertFalse(output.exists())

    def test_rejects_non_bbr_contract(self) -> None:
        contract = copy.deepcopy(CONTRACT)
        contract["streamSettings"]["finalmask"]["quicParams"]["congestion"] = "brutal"
        result, output, temp = self.run_merge(contract=contract)
        self.addCleanup(temp.cleanup)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("BBR", result.stderr)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
