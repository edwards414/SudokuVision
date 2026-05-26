import json
import subprocess
import sys


def test_cli_health_outputs_json_status():
    completed = subprocess.run(
        [sys.executable, "-m", "sudoku_vision.cli", "health"],
        check=True,
        capture_output=True,
        text=True,
    )

    payload = json.loads(completed.stdout)
    assert payload["status"] == "ok"
    assert payload["service"] == "sudoku-vision"
