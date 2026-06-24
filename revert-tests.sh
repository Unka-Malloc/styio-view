#!/bin/bash
cd /home/unka/Unka-Malloc/vityo-nightly
git checkout 11764926 -- frontend/vityo_app/test/shell_runtime_file_binding_test.dart
git checkout 11764926 -- frontend/vityo_app/test/shell_model_test.dart
echo "reverted to commit 11764926"
