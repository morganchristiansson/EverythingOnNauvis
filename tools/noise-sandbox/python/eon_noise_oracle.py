"""Batch client for the Rust Factorio noise oracle.

Python owns orchestration and reporting; the subprocess owns Factorio numerical
primitives. Requests are newline-delimited JSON so a caller can evaluate large
grids without starting a process per tile.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any, Iterable


class OracleError(RuntimeError):
    pass


class RustNoiseOracle:
    def __init__(self, executable: str | Path | None = None):
        root = Path(__file__).resolve().parents[1]
        self.executable = str(executable or root / "vendor" / "FactorioMapWebUI" / "target" / "debug" / "fmw-oracle")
        self.process = subprocess.Popen(
            [self.executable],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

    def __enter__(self) -> "RustNoiseOracle":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()

    def close(self) -> None:
        if self.process.stdin:
            self.process.stdin.close()
        self.process.wait(timeout=10)
        if self.process.returncode:
            error = self.process.stderr.read() if self.process.stderr else ""
            raise OracleError(f"noise oracle exited {self.process.returncode}: {error}")

    def request(self, request: dict[str, Any]) -> Any:
        assert self.process.stdin and self.process.stdout
        self.process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        response = json.loads(self.process.stdout.readline())
        if not response.get("ok"):
            raise OracleError(response.get("error", "unknown oracle error"))
        return response["value"]

    def batch(self, requests: Iterable[dict[str, Any]]) -> list[float]:
        requests = list(requests)
        if not requests:
            return []
        assert self.process.stdin and self.process.stdout
        payload = "".join(json.dumps(request, separators=(",", ":")) + "\n" for request in requests)
        self.process.stdin.write(payload)
        self.process.stdin.flush()
        values = []
        for _ in requests:
            response = json.loads(self.process.stdout.readline())
            if not response.get("ok"):
                raise OracleError(response.get("error", "unknown oracle error"))
            values.append(float(response["value"]))
        return values

    def basis_noise(self, x: float, y: float, seed0: int, seed1: int, input_scale: float = 1.0, output_scale: float = 1.0) -> float:
        return self.batch([{
            "op": "basis_noise", "x": x, "y": y, "seed0": seed0, "seed1": seed1,
            "input_scale": input_scale, "output_scale": output_scale,
        }])[0]
