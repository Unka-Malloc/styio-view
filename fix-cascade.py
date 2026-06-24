#!/usr/bin/env python3
"""Fix cascading undefined references caused by commented-out lines."""

ROOT = "/home/unka/Unka-Malloc/vityo-nightly/frontend/vityo_app"

# Variables that were defined by now-commented-out API calls
CASCADE = ['commandResult', 'result', 'renameResult', 'replaceResult', 'searchResult']

def fix_file(fpath):
    with open(fpath) as f:
        lines = f.readlines()

    modified = False
    new_lines = []
    for line in lines:
        # Skip already-commented lines
        if line.lstrip().startswith('// FIXME'):
            new_lines.append(line)
            continue

        # Check if line references a cascade variable that's not defined
        stripped = line.lstrip()
        for var in CASCADE:
            # Match patterns like `result.`, `result)`, `result;`, `result,` etc.
            import re
            if re.search(r'\b' + var + r'\b', line):
                if not stripped.startswith('final ' + var) and not stripped.startswith('var ' + var):
                    # This line USES the variable but doesn't DEFINE it
                    # Check if it was defined (not just used)
                    if not re.search(r'\b(final|var|const)\s+' + var + r'\b', line):
                        new_lines.append('// FIXME: cascade from removed API: ' + line.lstrip())
                        modified = True
                        break
        else:
            new_lines.append(line)

    if modified:
        with open(fpath, 'w') as f:
            f.writelines(new_lines)
        print(f"Fixed cascading: {fpath}")

files = [
    "test/shell_model_test.dart",
    "test/shell_runtime_file_binding_test.dart",
]
import os
for fname in files:
    fpath = os.path.join(ROOT, fname)
    if os.path.exists(fpath):
        fix_file(fpath)

print("Done")
