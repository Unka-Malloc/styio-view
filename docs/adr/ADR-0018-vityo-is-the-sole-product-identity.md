# ADR-0018: Vityo Is The Sole Product Identity

**Purpose:** 冻结 Vityo 与外部 Styio 语言工具链之间的命名和所有权边界。

**Last updated:** 2026-07-28

**Status:** Accepted

**Date:** 2026-07-28

## Context

Vityo 消费 Styio 语言、编译器、工具链和 `styio_lspd` 语言服务。依赖接入曾错误地把外部
依赖身份扩散到产品目录、Dart package、应用标题、bundle ID、安装器、发布产物、质量脚本和
产品计划，造成产品所有权与依赖所有权混淆。该变化没有对应的 Owner Decision，也与仓库现有
产品规格、交付基线和仓库名称冲突。

产品身份一旦进入安装 ID、包名和发布产物就具有高迁移成本。若不冻结边界，后续 Styio
服务接入会继续放大错误，并使外部依赖能够隐式决定本仓产品身份。

## Decision

1. Vityo 是本仓唯一产品和仓库身份。
2. 应用标题、产品目录、Vityo-owned package、安装 ID、bundle ID、发布产物、CI job、
   质量脚本、产品计划和用户可见文案只能使用 Vityo 派生身份。
3. Styio 只命名外部语言、编译器、工具链、语言文件、语言语义和 Styio-owned integration
   contract。
4. StyioService / `styio_lspd` 保留其外部服务身份，并通过明确 adapter 边界被 Vityo 消费；
   该身份不得扩散成 Vityo 的产品或发布身份。
5. 本次修正一次性迁移所有错误身份，不保留旧 package、路径、安装 ID 或兼容别名。
6. 未来任何产品改名必须先有明确的 Owner Decision，再执行原子化全仓迁移；依赖接入、
   架构重组或实现提交不能隐式改名。

## Consequences

1. 主 Flutter package 恢复为 `vityo_app`，平台应用名称恢复为 `Vityo`，既有 Vityo
   application/bundle identity 恢复为权威值。
2. Coding Agent 与共享协议仍保持独立可验收边界，但归属和命名统一为 Vityo。
3. Styio 语言服务、compiler/toolchain 类型、`.styio` 文件语义和 `styio_lspd` 名称不变。
4. 门禁需要同时验证 Vityo 产品身份和 Styio 依赖边界，防止依赖名再次进入产品 identity。
5. 本次迁移不回滚产品线拆分本身，只纠正未经授权的命名和由其派生的路径、配置与证据。

## Alternatives

1. 保留错误身份作为兼容别名：会继续制造双产品身份，并让新代码持续依赖错误路径。
2. 回滚整个产品线拆分：能恢复部分旧名，但会丢失已经形成的独立产品、协议和验证边界。
3. 只改用户可见标题：无法修复 package、bundle、安装和 CI 中的所有权漂移。

## Related Records

- `CONTEXT.md`
- `docs/design/Vityo-Product-Spec.md`
- `docs/design/Vityo-Delivered-Design-Baseline.md`
- `docs/review/Vityo-Owner-Decision-Queue.md`
- `docs/README.md`
