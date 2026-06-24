#!/bin/bash
cd /home/unka/Unka-Malloc/vityo-nightly
git add .
git commit -m "fix: comment out removed ShellRuntimeModel API in shell_runtime_file_binding_test"
git push origin HEAD:integration/nightly-all-subbranches-20260624
