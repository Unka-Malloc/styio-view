#!/bin/bash
cd /home/unka/Unka-Malloc/vityo-nightly
git add .
git commit -m "fix: remove all remaining ShellModel/ShellRuntimeModel API references in tests
- Comment out removed getters/methods in shell_model_test, vityo_app_smoke_test, shell_runtime_file_binding_test, workspace_edge_helpers_test
- Fix ambiguous DebugSessionSnapshot/Status imports in runtime_surfaces_test"
git push origin HEAD:integration/nightly-all-subbranches-20260624
