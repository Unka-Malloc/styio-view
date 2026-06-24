#!/bin/bash
cd /home/unka/Unka-Malloc/vityo-nightly
git add .
git commit -m "fix: resolve Flutter/Dart compilation errors"
git push origin HEAD:integration/nightly-all-subbranches-20260624
