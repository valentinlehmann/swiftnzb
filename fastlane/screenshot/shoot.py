#!/usr/bin/env python3
"""Drive a simulator to each screenshot state, capture it, and frame it.

No UI automation. The app's own persisted state is seeded before launch, and a DEBUG-only
`-startSection` launch argument opens the right tab, so every shot is deterministic. The queue
shot is a genuinely running download: a seeded `.queued` job makes DownloadManager.start() pick it
up and hit the real server, and the capture waits for actual bytes rather than a fixed delay.

Filenames in the seeded history come from docs/AppStoreReview.md § 5, which prescribes a safe
palette for anything visible in a screenshot.
"""
import argparse, json, os, plistlib, subprocess, sys, time, uuid, xml.etree.ElementTree as ET

BUNDLE = "de.valentinlehmann.swiftnzb"
# JSONEncoder's default date strategy is secondsSince2001, not Unix epoch.
APPLE_EPOCH_OFFSET = 978307200.0


def sh(*args, check=True, capture=True):
    r = subprocess.run(args, capture_output=capture, text=True)
    if check and r.returncode != 0:
        sys.exit(f"failed: {' '.join(args)}\n{r.stderr or r.stdout}")
    return (r.stdout or "").strip()


def apple_time(unix_ts):
    return unix_ts - APPLE_EPOCH_OFFSET


def container(sim):
    """The app's live data container, straight from simctl.

    Scanning the Application directory for a matching metadata plist is not good enough: reinstalls
    leave stale containers behind that still claim the bundle id, and picking the wrong one seeds a
    directory the app has abandoned.
    """
    r = subprocess.run(["xcrun", "simctl", "get_app_container", sim, BUNDLE, "data"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit(f"no {BUNDLE} container on {sim}; install the app first\n{r.stderr}")
    return r.stdout.strip()


def prefs_path(cont):
    return os.path.join(cont, "Library", "Preferences", f"{BUNDLE}.plist")


def read_prefs(cont):
    p = prefs_path(cont)
    if not os.path.isfile(p):
        return {}
    with open(p, "rb") as f:
        return plistlib.load(f)


def write_prefs(cont, d):
    p = prefs_path(cont)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        plistlib.dump(d, f)


def server_id(cont):
    raw = read_prefs(cont).get("servers.v1")
    if not raw:
        return None
    try:
        return json.loads(bytes(raw)).__getitem__(0).get("id")
    except Exception:
        return None


def jobs_path(cont):
    p = os.path.join(cont, "Library", "Application Support")
    os.makedirs(p, exist_ok=True)
    return os.path.join(p, "jobs.v1.json")


def segment(msgid, nbytes, number):
    return {"id": str(uuid.uuid4()).upper(), "messageID": msgid,
            "byteCount": nbytes, "number": number}


def nzb_files(path, limit_files=None):
    """Parse the real NZB into NZBFileSummary dicts, so the queue shot downloads real articles."""
    ns = {"n": "http://www.newzbin.com/DTD/2003/nzb"}
    root = ET.parse(path).getroot()
    out = []
    for fe in root.findall("n:file", ns):
        subject = fe.get("subject", "")
        name = subject.split('"')[1] if '"' in subject else subject
        groups = [g.text for g in fe.findall("n:groups/n:group", ns) if g.text]
        segs = []
        for se in fe.findall("n:segments/n:segment", ns):
            segs.append(segment((se.text or "").strip(),
                                int(se.get("bytes", 0)), int(se.get("number", 0))))
        segs.sort(key=lambda s: s["number"])
        out.append({"id": str(uuid.uuid4()).upper(), "subject": subject, "filename": name,
                    "groups": groups, "segments": segs,
                    "totalBytes": sum(s["byteCount"] for s in segs), "downloadedBytes": 0})
        if limit_files and len(out) >= limit_files:
            break
    return out


def finished_file(name, nbytes):
    # Completed jobs have their per-segment metadata dropped, so history rows carry none either.
    return {"id": str(uuid.uuid4()).upper(), "subject": name, "filename": name,
            "groups": ["alt.binaries.example"], "segments": [],
            "totalBytes": nbytes, "downloadedBytes": nbytes}


def job(name, status, files, srv, *, added_ago, completed_ago=None, folder=None):
    now = time.time()
    total = sum(f["totalBytes"] for f in files)
    done = sum(f["downloadedBytes"] for f in files)
    j = {"id": str(uuid.uuid4()).upper(), "name": name, "status": status, "files": files,
         "totalBytes": total, "downloadedBytes": done,
         "addedAt": apple_time(now - added_ago)}
    if completed_ago is not None:
        j["completedAt"] = apple_time(now - completed_ago)
    if folder:
        j["completedFolderRelativePath"] = folder
    if srv:
        j["assignedServerID"] = srv
    return j


# Names from docs/AppStoreReview.md § 5 — never anything release-shaped.
HISTORY = [
    ("ubuntu-24.04-desktop-amd64", "ubuntu-24.04-desktop-amd64.iso", 5_063_446_528, 1_800, "ubuntu-24.04-desktop-amd64"),
    ("project-backup-2026", "project-backup-2026.rar", 2_147_483_648, 26_400, "project-backup-2026"),
    ("openstreetmap-europe-extract", "openstreetmap-europe-extract.pbf", 28_991_029_248, 93_600, "openstreetmap-europe-extract"),
    ("holiday-photos", "holiday-photos.zip", 1_288_490_188, 180_000, "holiday-photos"),
]


def seed(cont, state, nzb, queue_mode="live"):
    srv = server_id(cont)
    prefs = read_prefs(cont)
    history = [job(n, "completed", [finished_file(f, b)], srv,
                   added_ago=ago + 600, completed_ago=ago, folder=folder)
               for n, f, b, ago, folder in HISTORY]

    if state == "queue":
        files = nzb_files(nzb)
        if queue_mode == "paused":
            # Mark the first stretch of files done and one mid-flight, so the queue renders real
            # progress without the engine needing to reach a server.
            done = 0
            for k, f in enumerate(files):
                if k < 17:
                    f["downloadedBytes"] = f["totalBytes"]
                elif k == 17:
                    f["downloadedBytes"] = int(f["totalBytes"] * 0.42)
                done += f["downloadedBytes"]
            jobs = [job("ubuntu-24.04-desktop-amd64", "paused", files, srv, added_ago=420)] + history
        else:
            jobs = [job("ubuntu-24.04-desktop-amd64", "queued", files, srv, added_ago=8)] + history
        prefs.pop("entitlement.freeDownloads.v1", None)
    elif state == "history":
        jobs = history
        prefs.pop("entitlement.freeDownloads.v1", None)
    elif state == "settings":
        jobs = history
        # Three slots spent -> the Settings row reads "7 free downloads left", which is the
        # 2.3.2 disclosure Apple wants visible in a screenshot.
        spent = sorted(str(uuid.uuid4()).upper() for _ in range(3))
        prefs["entitlement.freeDownloads.v1"] = json.dumps(spent).encode()
    else:
        sys.exit(f"unknown state {state}")

    # Never let a stale Pro flag hide the free-download count.
    prefs.pop("entitlement.cachedPro.v1", None)
    prefs.pop("entitlement.grandfathered.v1", None)
    write_prefs(cont, prefs)
    with open(jobs_path(cont), "w") as f:
        json.dump(jobs, f)
    return cont


def launch(sim, sect, locale="en_US", language="en"):
    """simctl launch right after a boot often loses a race with SpringBoard, so retry it.

    AppleLocale and AppleLanguages are passed as launch arguments, which land in the app's
    UserDefaults and drive every Formatter. Without them the shot inherits the simulator's own
    locale and an en-US screenshot ends up reading "5,06 GB" and "8. Sept. 2026".
    """
    last = ""
    # bootstatus returns before SpringBoard will actually accept an open request, and the gap
    # after a shutdown/boot cycle can run past half a minute, so be patient here.
    subprocess.run(["xcrun", "simctl", "terminate", sim, BUNDLE], capture_output=True)
    for attempt in range(25):
        r = subprocess.run(["xcrun", "simctl", "launch", sim, BUNDLE, "-startSection", sect,
                            "-AppleLocale", locale, "-AppleLanguages", f"({language})"],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return
        last = (r.stderr or r.stdout).strip()
        time.sleep(3)
    sys.exit(f"could not launch after 25 attempts:\n{last}")


def wait_for_progress(cont, min_bytes, timeout):
    """Wait for the engine to report real decoded bytes, instead of guessing at a delay."""
    deadline = time.time() + timeout
    best = 0
    while time.time() < deadline:
        try:
            with open(jobs_path(cont)) as f:
                for j in json.load(f):
                    if j.get("status") in ("downloading", "queued"):
                        best = max(best, j.get("downloadedBytes", 0))
        except Exception:
            pass
        if best >= min_bytes:
            return best
        time.sleep(1.5)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", required=True)
    ap.add_argument("--app", required=True, help="path to the built .app")
    ap.add_argument("--nzb", required=True)
    ap.add_argument("--bezel", required=True)
    ap.add_argument("--background", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--states", default="queue,history,settings")
    ap.add_argument("--settle", type=float, default=6.0)
    ap.add_argument("--locale", default="en_US")
    ap.add_argument("--language", default="en")
    ap.add_argument("--queue-mode", choices=("live", "paused"), default="live",
                    help="live runs a real download; paused seeds partial progress instead, for "
                         "when the simulator has no working server credential")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))

    # Install once, before any seeding. simctl install can rotate the app's data container, so
    # anything written beforehand ends up in a container the app then abandons.
    print("[install]")
    sh("xcrun", "simctl", "boot", a.sim, check=False)
    sh("xcrun", "simctl", "bootstatus", a.sim, "-b")
    sh("xcrun", "simctl", "install", a.sim, a.app)
    sh("xcrun", "simctl", "terminate", a.sim, BUNDLE, check=False)
    cont = container(a.sim)          # only answerable while booted
    print(f"  container {cont[-12:]}")

    section = {"queue": "queue", "history": "history", "settings": "settings"}
    for i, state in enumerate(a.states.split(","), start=1):
        print(f"[{state}]")
        # Shut down before editing preferences, or cfprefsd writes its cached copy back over them.
        sh("xcrun", "simctl", "shutdown", a.sim, check=False)
        seed(cont, state, a.nzb, a.queue_mode)
        sh("xcrun", "simctl", "boot", a.sim, check=False)
        sh("xcrun", "simctl", "bootstatus", a.sim, "-b")
        launch(a.sim, section[state], a.locale, a.language)
        # If the seed failed to decode, JobStore sets the file aside and the queue comes up empty.
        for stray in os.listdir(os.path.dirname(jobs_path(cont))):
            if stray.startswith("jobs.corrupt-"):
                sys.exit(f"seed did not decode: JobStore quarantined it as {stray}")
        if state == "queue" and a.queue_mode == "live":
            got = wait_for_progress(cont, 8_000_000, 90)
            if got == 0:
                print("  no bytes decoded. The server login is failing, or the simulator has no "
                      "password in its keychain. Re-run with --queue-mode paused for a static "
                      "progress shot.")
            else:
                print(f"  live download reached {got / 1e6:.1f} MB decoded")
        time.sleep(a.settle)
        raw = os.path.join(a.out, f"{i:02d}-{state}-raw.png")
        sh("xcrun", "simctl", "io", a.sim, "screenshot", "--type=png", raw)
        final = os.path.join(a.out, f"{i:02d}-{state}.png")
        sh(sys.executable, os.path.join(here, "compose.py"), "--shot", raw,
           "--bezel", a.bezel, "--background", a.background, "--out", final, capture=False)
        print(f"  {final}")


if __name__ == "__main__":
    main()
