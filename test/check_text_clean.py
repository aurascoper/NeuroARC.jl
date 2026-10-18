#!/usr/bin/env python3
"""
Audit repository text for epistemic invariants:
1. Strictly 0 em-dashes (\u2014)
2. Strictly 0 en-dashes (\u2013)
3. Strictly 0 quarantined terms:
   - "free-will" + " " + "octane"
   - "radiotrophic" + " " + "methanogen"
"""
import os
import sys

def check_text_cleanliness(root_dir):
    violations = []
    checked_files = 0

    # Quarantined terms split to prevent self-detection
    quarantined = [
        "free-will" + " " + "octane",
        "radiotrophic" + " " + "methanogen",
        "proto" + "bacter",
        "radio" + "gyrism",
        "sobolev" + " " + "chemostatin",
        "filter-empowered" + " " + "gyre"
    ]

    skip_dirs = {".git", "__pycache__", ".pytest_cache", ".ruff_cache", "build"}
    valid_exts = {
        ".jl", ".py", ".md", ".tex", ".bib", ".yml", ".yaml",
        ".json", ".txt", ".sh", ".toml", ".dot", ".svg"
    }

    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in skip_dirs]
        for f in filenames:
            ext = os.path.splitext(f)[1].lower()
            if ext not in valid_exts:
                continue
            path = os.path.join(dirpath, f)
            # Skip this checker script itself
            if os.path.abspath(path) == os.path.abspath(__file__):
                continue
            checked_files += 1
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fp:
                    content = fp.read()
            except Exception as e:
                violations.append((path, f"Could not read file: {e}"))
                continue

            if "\u2014" in content:
                violations.append((path, "Found em-dash (\\u2014)"))
            if "\u2013" in content:
                violations.append((path, "Found en-dash (\\u2013)"))
            for q in quarantined:
                if q in content.lower():
                    violations.append((path, f"Found quarantined term: {q}"))

    print(f"Scanned {checked_files} text/code files across {root_dir}")
    if violations:
        print(f"FAILED: Found {len(violations)} policy violations:")
        for path, reason in violations:
            print(f"  - {path}: {reason}")
        return False
    else:
        print("PASSED: 0 em-dashes, 0 en-dashes, 0 quarantined terms verified.")
        return True

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    success = check_text_cleanliness(target)
    sys.exit(0 if success else 1)
