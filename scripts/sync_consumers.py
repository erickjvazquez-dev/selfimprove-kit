#!/usr/bin/env python3
"""Bring a repo that uses the kit up to date with the kit's current skills and hooks.

A consumer's copy of a kit file is *pristine* when its blob matches any version the
kit ever committed for that file; pristine copies are replaced with the current one.
Anything else is *customized*: left untouched and reported with the kit commits it
has not received. See .claude/specs/consumer-sync.md.

  sync_consumers.py --consumer PATH [--name N] [--skills-dir D] [--hooks-dir D]
                    [--add-missing] [--rename-custom-loop] [--enable-plugin]
  sync_consumers.py --registry consumers.json     # print entries, one JSON per line
  sync_consumers.py --selftest
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT_REPO = "erickjvazquez-dev/selfimprove-kit"
PLUGIN_KEY = "selfimprove-kit@selfimprove-kit"
STAMP = ".claude/selfimprove-kit.json"
GATE = "## Step −1 — Project routing gate"
ROUTED = ("- **You are already running as `/self-improve-<name>`** (this engine was copied into a\n"
          "  bespoke loop) → skip this gate and continue below; routing already happened.\n")


def git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, check=True).stdout


def norm(text):
    # Line endings and trailing whitespace are editor noise, not customization.
    return "\n".join(line.rstrip() for line in text.replace("\r\n", "\n").split("\n")).strip()


def read(path):
    return open(path, encoding="utf-8", errors="replace").read()


def kit_versions(kit, rel):
    out = git(kit, "log", "--all", "--format=", "--raw", "--no-abbrev", "--", rel)
    blobs = {b for line in out.splitlines() for b in line.split()[2:4] if not set(b) <= {"0"}}
    return {norm(git(kit, "cat-file", "-p", b)) for b in blobs}


def project_name(consumer, override):
    if override:
        return override.lower()
    env = os.path.join(consumer, ".ccf", "project.env")
    if os.path.exists(env):
        m = re.search(r'^CCF_PROJECT_NAME=["\']?([^"\'\n]+)', open(env).read(), re.M)
        if m and m.group(1).strip():
            return m.group(1).strip().lower()
    return os.path.basename(os.path.abspath(consumer)).lower()


def kit_hook(kit, name):
    for d in ("core/hooks", "hooks"):
        if os.path.isfile(os.path.join(kit, d, name)):
            return f"{d}/{name}"
    return None


def enable_plugin(consumer):
    p = os.path.join(consumer, ".claude", "settings.json")
    cur = json.load(open(p)) if os.path.exists(p) else {}
    new = json.loads(json.dumps(cur))
    mk = new.setdefault("extraKnownMarketplaces", {})
    mk.pop("claude-code-framework", None)
    mk["selfimprove-kit"] = {"source": {"source": "github", "repo": KIT_REPO}, "autoUpdate": True}
    ep = new.setdefault("enabledPlugins", {})
    for k in [k for k in ep if k.startswith("claude-code-framework@")]:
        ep.pop(k)
    ep[PLUGIN_KEY] = True
    if new == cur:
        return False
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(json.dumps(new, indent=2) + "\n")
    return True


def sync(consumer, kit=KIT, name=None, skills_dir=".claude/commands", hooks_dir=".claude/hooks",
         add_missing=False, rename_custom_loop=False, plugin=False):
    r = {"updated": [], "added": [], "renamed": [], "customized": [], "settings": False}
    stamp_p = os.path.join(consumer, STAMP)
    last_sha = json.load(open(stamp_p)).get("kit_sha") if os.path.exists(stamp_p) else None
    head = git(kit, "rev-parse", "HEAD").strip()

    pairs = []
    for f in sorted(os.listdir(os.path.join(kit, "commands"))):
        if f.endswith(".md"):
            pairs.append((f"commands/{f}", os.path.join(skills_dir, f), True))
    hd = os.path.join(consumer, hooks_dir)
    if os.path.isdir(hd):
        for f in sorted(os.listdir(hd)):
            rel = kit_hook(kit, f)
            if rel:
                pairs.append((rel, os.path.join(hooks_dir, f), False))

    loop = project_name(consumer, name)
    for kit_rel, cons_rel, is_skill in pairs:
        src, dst = os.path.join(kit, kit_rel), os.path.join(consumer, cons_rel)
        if not os.path.exists(dst):
            if is_skill and add_missing:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst)
                r["added"].append(cons_rel)
            continue
        have = norm(read(dst))
        if have == norm(read(src)):
            continue
        if have in kit_versions(kit, kit_rel):
            shutil.copyfile(src, dst)
            r["updated"].append(cons_rel)
            continue
        if is_skill and rename_custom_loop and os.path.basename(cons_rel) == "self-improve.md":
            target = os.path.join(os.path.dirname(dst), f"self-improve-{loop}.md")
            if not os.path.exists(target):
                os.rename(dst, target)
                body = read(target)
                if GATE in body and "already running as `/self-improve-" not in body:
                    before, _, rest = body.partition(GATE)
                    line_end = rest.index("\n") + 1
                    open(target, "w").write(before + GATE + rest[:line_end] + "\n" + ROUTED + rest[line_end:])
                shutil.copyfile(src, dst)
                r["renamed"].append([cons_rel, os.path.relpath(target, consumer)])
                continue
        rng = [f"{last_sha}..HEAD"] if last_sha else ["-5"]
        missed = git(kit, "log", "--oneline", *rng, "--", kit_rel).strip().splitlines()
        r["customized"].append({"file": cons_rel, "kit_commits": missed})

    if plugin:
        r["settings"] = enable_plugin(consumer)
    if r["updated"] or r["added"] or r["renamed"] or r["settings"]:
        os.makedirs(os.path.dirname(stamp_p), exist_ok=True)
        open(stamp_p, "w").write(json.dumps(
            {"kit_repo": KIT_REPO, "kit_sha": head, "synced_at": datetime.date.today().isoformat()},
            indent=2) + "\n")
    r["changed"] = bool(r["updated"] or r["added"] or r["renamed"] or r["settings"])
    r["kit_sha"] = head
    return r


def report_md(r):
    lines = [f"Synced with selfimprove-kit `{r['kit_sha'][:7]}`.", ""]
    for key, title in (("updated", "Updated (unmodified kit copies)"), ("added", "Added")):
        if r[key]:
            lines += [f"**{title}:** " + ", ".join(f"`{x}`" for x in r[key]), ""]
    for a, b in r["renamed"]:
        lines += [f"**Renamed customized loop:** `{a}` → `{b}`; the generic engine now routes `/self-improve` to it.", ""]
    if r["settings"]:
        lines += ["**Settings:** enabled the `selfimprove-kit` plugin with `autoUpdate` for local CLI sessions.", ""]
    if r["customized"]:
        lines += ["**Customized — left untouched.** Kit changes these copies have not received:", ""]
        for c in r["customized"]:
            lines.append(f"- `{c['file']}`")
            lines += [f"  - {m}" for m in c["kit_commits"]] or ["  - (none)"]
    return "\n".join(lines).rstrip() + "\n"


def selftest():
    t = tempfile.mkdtemp()
    try:
        kit, cons = os.path.join(t, "kit"), os.path.join(t, "Cons")
        env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                   GIT_COMMITTER_EMAIL="t@t")

        def commit(files, msg):
            for rel, body in files.items():
                os.makedirs(os.path.dirname(os.path.join(kit, rel)), exist_ok=True)
                open(os.path.join(kit, rel), "w").write(body)
            subprocess.run(["git", "-C", kit, "add", "-A"], check=True, env=env)
            subprocess.run(["git", "-C", kit, "commit", "-qm", msg], check=True, env=env)

        os.makedirs(kit)
        subprocess.run(["git", "init", "-q", kit], check=True)
        commit({"commands/foo.md": "foo v1\n", "commands/baz.md": "baz v1\n", "commands/bar.md": "bar\n",
                "commands/self-improve.md": "engine v1\n", "core/hooks/h.sh": "h v1\n"}, "v1")
        commit({"commands/foo.md": "foo v2\n", "commands/baz.md": "baz v2\n",
                "commands/self-improve.md": "engine v2\n", "core/hooks/h.sh": "h v2\n"}, "v2")
        cd, hd = os.path.join(cons, ".claude/commands"), os.path.join(cons, ".claude/hooks")
        os.makedirs(cd), os.makedirs(hd)
        open(os.path.join(cd, "foo.md"), "w", newline="").write("foo v1  \r\n")
        open(os.path.join(cd, "baz.md"), "w").write("baz customized\n")
        open(os.path.join(cd, "self-improve.md"), "w").write(f"my own loop\n{GATE} (RUN FIRST)\nroute\n")
        open(os.path.join(cd, "mine.md"), "w").write("project skill\n")
        open(os.path.join(hd, "h.sh"), "w").write("h v1\n")
        open(os.path.join(hd, "private.sh"), "w").write("export TOKEN=x\n")
        json.dump({"theme": "dark", "enabledPlugins": {"claude-code-framework@claude-code-framework": True,
                                                        "other@x": True}},
                  open(os.path.join(cons, ".claude/settings.json"), "w"))

        r = sync(cons, kit, add_missing=True, rename_custom_loop=True, plugin=True)
        rd = lambda *p: open(os.path.join(cons, *p)).read()
        assert rd(".claude/commands/foo.md") == "foo v2\n", "pristine copy not updated"
        assert rd(".claude/commands/baz.md") == "baz customized\n", "customized copy overwritten"
        assert [c["file"] for c in r["customized"]] == [".claude/commands/baz.md"], r["customized"]
        assert rd(".claude/commands/bar.md") == "bar\n", "missing skill not added"
        loop = rd(".claude/commands/self-improve-cons.md")
        assert loop.startswith("my own loop\n"), "custom loop not renamed"
        assert loop.index(ROUTED) > loop.index(GATE), "renamed loop would route to itself"
        assert rd(".claude/commands/self-improve.md") == "engine v2\n", "generic engine not added"
        assert rd(".claude/commands/mine.md") == "project skill\n"
        assert rd(".claude/hooks/h.sh") == "h v2\n", "pristine hook not updated"
        assert rd(".claude/hooks/private.sh") == "export TOKEN=x\n"
        s = json.loads(rd(".claude/settings.json"))
        assert s["theme"] == "dark" and s["enabledPlugins"].get("other@x") is True, "settings keys lost"
        assert PLUGIN_KEY in s["enabledPlugins"], "plugin not enabled"
        assert not any(k.startswith("claude-code-framework@") for k in s["enabledPlugins"]), "stale key kept"
        assert s["extraKnownMarketplaces"]["selfimprove-kit"]["autoUpdate"] is True
        assert os.path.exists(os.path.join(cons, STAMP)) and r["changed"]

        st = json.loads(rd(STAMP)); st["synced_at"] = "2000-01-01"
        open(os.path.join(cons, STAMP), "w").write(json.dumps(st))
        before = {p: open(os.path.join(dp, p)).read() for dp, _, fs in os.walk(cons) for p in fs}
        r2 = sync(cons, kit, add_missing=True, rename_custom_loop=True, plugin=True)
        after = {p: open(os.path.join(dp, p)).read() for dp, _, fs in os.walk(cons) for p in fs}
        assert not r2["changed"] and before == after, "second run was not a no-op"
        print("  ok: consumer-sync selftest passed")
    finally:
        shutil.rmtree(t, ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--consumer")
    ap.add_argument("--name")
    ap.add_argument("--skills-dir", default=".claude/commands")
    ap.add_argument("--hooks-dir", default=".claude/hooks")
    ap.add_argument("--add-missing", action="store_true")
    ap.add_argument("--rename-custom-loop", action="store_true")
    ap.add_argument("--enable-plugin", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--registry")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.registry:
        for c in json.load(open(a.registry))["consumers"]:
            print(json.dumps(c))
        return
    if not a.consumer:
        ap.error("--consumer, --registry or --selftest is required")
    r = sync(a.consumer, name=a.name, skills_dir=a.skills_dir, hooks_dir=a.hooks_dir,
             add_missing=a.add_missing, rename_custom_loop=a.rename_custom_loop, plugin=a.enable_plugin)
    print(json.dumps(r, indent=2) if a.json else report_md(r))


if __name__ == "__main__":
    sys.exit(main())
