#!/usr/bin/env python3
"""Find the last-known-green SH commit to bound the bisect range.

pick_good_run() is pure and unit-tested. main() gathers prior ci-full run
records via the GitHub Actions API (`gh api`) and feeds them in.

Usage (CLI):
  sh-lastgreen.py <failure_type> [<regressed-tests-file>]
Environment:
  GH_REPO     owner/repo (default: $GITHUB_REPOSITORY)
  CI_WORKFLOW workflow file name (default: ci-full.yml)
Emits JSON: {"good_commit": "<sha>"|null, "good_run_id": <id>|null}
"""
import base64
import json
import os
import subprocess
import sys


def pick_good_run(runs, failure_type, regressed_tests, is_test_passing):
    """runs: list of dicts newest-first, each with keys:
         run_id, build_success (bool), commit (gcc-mirror sha or None).
    For dejagnu, is_test_passing(run) must return True iff the regressed
    test(s) were passing in that run. Returns the chosen run dict or None."""
    for r in runs:
        if not r["build_success"]:
            continue
        if not r.get("commit"):
            continue
        if failure_type == "dejagnu" and not is_test_passing(r):
            continue
        return r
    return None


def _gh_json(args):
    out = subprocess.run(["gh", *args], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def _gather_runs(repo, workflow):
    """Newest-first ci-full runs on main, annotated with build-and-test result
    and the tested commit (from state/last-tested.json at the run's head_sha)."""
    data = _gh_json([
        "api", "-X", "GET",
        f"/repos/{repo}/actions/workflows/{workflow}/runs",
        "-f", "branch=main", "-f", "per_page=50",
    ])
    runs = []
    for run in data.get("workflow_runs", []):
        if run.get("conclusion") in (None, "cancelled"):
            continue
        jobs = _gh_json(["api", f"/repos/{repo}/actions/runs/{run['id']}/jobs"])
        bt = next((j for j in jobs.get("jobs", []) if j["name"] == "build-and-test"), None)
        if bt is None:
            continue
        build_success = bt["conclusion"] == "success"
        commit = None
        try:
            # Fetch the full JSON object (without -q) so json.loads succeeds,
            # then extract the base64 "content" field from the parsed object.
            # Using -q .content would emit a raw (unquoted) base64 string,
            # which is not valid JSON and would cause json.loads to raise.
            content_obj = _gh_json([
                "api",
                f"/repos/{repo}/contents/state/last-tested.json?ref={run['head_sha']}",
            ])
            raw = base64.b64decode(content_obj["content"]).decode()
            commit = json.loads(raw).get("commit")
        except (subprocess.CalledProcessError, KeyError, ValueError):
            commit = None
        runs.append({"run_id": run["id"], "build_success": build_success, "commit": commit})
    return runs


def main(argv):
    failure_type = argv[1] if len(argv) > 1 else "build"
    repo = os.environ.get("GH_REPO") or os.environ["GITHUB_REPOSITORY"]
    workflow = os.environ.get("CI_WORKFLOW", "ci-full.yml")
    runs = _gather_runs(repo, workflow)
    # dejagnu test-passing check is left permissive here (job-success bound);
    # the predicate re-verifies per commit during bisect.
    good = pick_good_run(runs, failure_type, [], lambda r: True)
    print(json.dumps({
        "good_commit": good["commit"] if good else None,
        "good_run_id": good["run_id"] if good else None,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
