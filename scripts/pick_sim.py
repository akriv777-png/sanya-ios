import json, subprocess, sys
d = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devs = []
for rt, lst in d["devices"].items():
    if "iOS" not in rt:
        continue
    ver = tuple(int(p) for p in rt.split("iOS-")[-1].split("-") if p.isdigit())
    for x in lst:
        devs.append((ver, x["name"], x["udid"]))
devs.sort(reverse=True)
for pref in ["iPhone 15", "iPhone 16", "iPhone 17", "iPhone 16 Pro", "iPhone 15 Pro", "iPhone 17 Pro"]:
    for v, n, u in devs:
        if n == pref:
            print(f"picked {n} iOS {v}", file=sys.stderr); print(u); sys.exit(0)
for v, n, u in devs:
    if n.startswith("iPhone"):
        print(f"picked {n} iOS {v}", file=sys.stderr); print(u); sys.exit(0)
sys.exit("no iPhone simulator")
