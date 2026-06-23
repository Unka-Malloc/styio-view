# Repository Hygiene UTF-8 Sampling Fix

**Purpose:** 记录 `guard-repository-hygiene` 门禁修复，确保 `Vityo` 在推送到受保护分支和上游主仓时不会因为 UTF-8 采样误判而错误拦截。

**Last updated:** 2026-04-19

**Date:** 2026-04-19

## 摘要

1. `scripts/check_repo_hygiene.py` 的二进制检测已修复，不再把合法的 UTF-8 Markdown 文档误判成 binary。
2. 本次修复不是加白名单，而是修正采样解码逻辑，使仓库门禁在本仓和上游主仓都保持可用。

## 现象

1. `docs/specs/UX-MAINTENANCE-GUIDELINES.md` 会被 `guard-repository-hygiene` 误报为 unexpected binary。
2. 误报会导致受保护分支所需的 `guard-repository-hygiene` 检查无法稳定通过，影响 `nightly` 与上游主仓的提交路径。

## 根因

1. 原逻辑只读取前 `8192` 字节，并对这个截断样本做严格 UTF-8 解码。
2. 当样本恰好截断在多字节字符中间时，会抛出 `UnicodeDecodeError: unexpected end of data`。
3. 脚本随后把这种“合法文本被截断”的情况错误归类成 binary。

## 修复

1. 二进制检测保留 `NUL byte => binary` 的快速判定。
2. UTF-8 文本判定改为 incremental decoder，允许样本在多字节字符中间结束而不误报。
3. 仍然保留控制字符筛查，避免把真实二进制内容放行成文本。

## 验证

```bash
python3 scripts/check_repo_hygiene.py
python3 scripts/docs-audit.py
```

## 下一步

1. 若后续继续扩 `check_repo_hygiene.py`，优先新增回归测试或最小 fixture，避免再次把合法 UTF-8 文档误判成 binary。
2. 继续把 `guard-repository-hygiene` 当成真实分支保护，而不是本地一次性检查。
