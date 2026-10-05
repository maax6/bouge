#!/usr/bin/env python3
"""Exercise Bouge's real test handler and check macOS banner presentation.

Run outside a shell sandbox: macOS notification IPC and unified logs are needed.
This sends two visible test notifications without changing the regular timer.
"""
import datetime
import json
import pathlib
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else
    str(pathlib.Path.home() / "Applications/Bouge.app")).resolve()
executable = app / "Contents/MacOS/Bouge"

def diagnostics():
    return json.loads(subprocess.check_output([str(executable), "--diagnostics"], text=True))

before = diagnostics()
if before["authorization"] != 2 or before["alertSetting"] != 2:
    sys.exit("FAIL: macOS notification/banner permission is disabled")

failures = []
for attempt in range(1, 3):
    previous_ids = {item["id"] for item in diagnostics()["delivered"] if item["id"].startswith("test-reminder")}
    start = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    subprocess.run(["open", "-a", str(app), "bouge://test"], check=True)
    time.sleep(3)
    log = subprocess.check_output([
        "/usr/bin/log", "show", "--start", start, "--style", "compact",
        "--predicate", 'process == "usernoted" AND eventMessage CONTAINS[c] "fr.m4ks.bouge" '
        'AND eventMessage CONTAINS[c] "test-reminder"'], text=True)
    banners = [line for line in log.splitlines() if
        "Presenting <NotificationRecord" in line and "as banner" in line]
    updates = [line for line in log.splitlines() if "updatedExisting: true" in line]
    suppression = [line for line in log.splitlines() if
        "Resolved event behavior=" in line and "interruptionSuppression:" in line
        and "interruptionSuppression: none;" not in line]
    delivered = [item for item in diagnostics()["delivered"] if item["id"].startswith("test-reminder")]
    fresh_ids = {item["id"] for item in delivered} - previous_ids
    if suppression or not banners or updates or not fresh_ids:
        reason = ("macOS Focus suppresses or delays the popup despite notification delivery" if suppression else
            "test reused a delivered notification ID" if delivered and not fresh_ids else
            "existing notification updated instead of a fresh banner" if updates else
            "no fresh banner recorded by macOS")
        failures.append(f"test {attempt}: {reason}")
        print(f"FAIL: test {attempt}: {reason}")
    else:
        print(f"PASS: test {attempt}: fresh banner recorded by macOS without Focus suppression; confirm visually")

after = diagnostics()
regular = lambda state: [item for item in state["pending"] if item["id"] == "position-reminder"]
if regular(before) != regular(after) or before["paused"] != after["paused"]:
    failures.append("test changed the regular reminder or pause state")
    print("FAIL: test changed the regular reminder or pause state")
else:
    print("PASS: regular reminder and pause state preserved")
sys.exit(1 if failures else 0)
