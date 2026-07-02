#!/usr/bin/env python3
"""Append a suffix to the `name` of every metric object read from stdin.

Usage:  suffix-metrics.py <suffix>  <in.json  >out.json
Input/output: a JSON array of {"name","unit","value"} objects.
"""
import json, sys

def main(argv):
    if len(argv) != 2:
        print("usage: suffix-metrics.py <suffix>", file=sys.stderr)
        return 2
    suffix = argv[1]
    data = json.load(sys.stdin)
    for entry in data:
        if isinstance(entry, dict) and "name" in entry:
            entry["name"] = f"{entry['name']}{suffix}"
    json.dump(data, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
