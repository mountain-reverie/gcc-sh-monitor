#!/usr/bin/env python3
"""Format the GitHub issue for an SH CI regression (pure; no gh calls).

Usage:
  sh-file-issue.py --title --result <result.json>
  sh-file-issue.py --body  --result <result.json>

Three states keyed off the result object:
  * bisected & culprit set         -> name the single culprit commit
  * bisected & exhausted           -> report the narrowed sub-range
  * not bisected (good_commit None)-> report first-red only, note no bound
"""
import json
import sys

GCC_COMMIT_URL = "https://github.com/gcc-mirror/gcc/commit/{sha}"
GCC_COMPARE_URL = "https://github.com/gcc-mirror/gcc/compare/{good}...{bad}"

def _short(sha):
    return sha[:12] if sha else "?"

def _what(r):
    if r["failure_type"] == "dejagnu":
        tests = r.get("regressed_tests") or []
        head = tests[0] if tests else "dejagnu regression"
        extra = f" (+{len(tests) - 1} more)" if len(tests) > 1 else ""
        return f"{head}{extra}"
    return r.get("failed_step") or "build failure"

def title(r):
    what = _what(r)
    if r.get("culprit"):
        return f"SH CI regression: {what} → gcc-mirror {_short(r['culprit'])}"
    if r.get("exhausted"):
        return (f"SH CI regression: {what} → range "
                f"{_short(r.get('narrowed_good'))}..{_short(r.get('narrowed_bad'))}")
    return (f"SH CI regression: {what} → range "
            f"{_short(r.get('good_commit'))}..{_short(r.get('bad_commit'))}")

def body(r):
    lines = []
    ft = r["failure_type"]
    lines.append("## Failure")
    lines.append("")
    if ft == "dejagnu":
        lines.append("New dejagnu test regression(s) (job stayed green, `.fail` non-empty):")
        for t in r.get("regressed_tests") or []:
            lines.append(f"- `{t}`")
    else:
        lines.append(f"`build-and-test` failed at step **{r.get('failed_step')}** "
                     f"(type: `{ft}`).")
    lines.append("")

    lines.append("## Culprit")
    lines.append("")
    if r.get("culprit"):
        url = GCC_COMMIT_URL.format(sha=r["culprit"])
        lines.append(f"Bisected to **{_short(r['culprit'])}** — {url}")
        if r.get("culprit_author") or r.get("culprit_subject"):
            lines.append("")
            lines.append(f"> {r.get('culprit_subject','')}  \n> — {r.get('culprit_author','')}")
    elif r.get("exhausted"):
        lines.append("Bisect ran out of its time budget and **could not be fully "
                     "bisected** (incomplete). Narrowed to:")
        lines.append("")
        lines.append(f"- good: {_short(r.get('narrowed_good'))} — "
                     f"{GCC_COMMIT_URL.format(sha=r.get('narrowed_good'))}")
        lines.append(f"- bad:  {_short(r.get('narrowed_bad'))} — "
                     f"{GCC_COMMIT_URL.format(sha=r.get('narrowed_bad'))}")
    else:
        lines.append("No bisect was run: the **last-green** commit bound could not "
                     "be established (no prior green run found in history). "
                     "First-red commit below.")
    lines.append("")

    good, bad = r.get("good_commit"), r.get("bad_commit")
    if good and bad:
        lines.append("## Bisected range")
        lines.append("")
        lines.append(GCC_COMPARE_URL.format(good=good, bad=bad))
        lines.append("")

    lines.append("## CI run")
    lines.append("")
    lines.append(r.get("run_url", ""))
    if r.get("log_excerpt"):
        lines.append("")
        lines.append("<details><summary>Failing step log (tail)</summary>")
        lines.append("")
        lines.append("```")
        lines.append(r["log_excerpt"])
        lines.append("```")
        lines.append("</details>")
    return "\n".join(lines)

def main(argv):
    if "--result" not in argv:
        print("usage: sh-file-issue.py <--title|--body> --result <file>", file=sys.stderr)
        return 2
    result = json.loads(open(argv[argv.index("--result") + 1]).read())
    if "--title" in argv:
        print(title(result))
    elif "--body" in argv:
        print(body(result))
    else:
        print("specify --title or --body", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
