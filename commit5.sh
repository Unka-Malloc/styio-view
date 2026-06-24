#!/bin/bash
cd /home/unka/Unka-Malloc/vityo-nightly
git add .
git commit -m "fix: resolve DebugSessionSnapshot ambiguity in runtime_surfaces_test"
git push origin HEAD:integration/nightly-all-subbranches-20260624
