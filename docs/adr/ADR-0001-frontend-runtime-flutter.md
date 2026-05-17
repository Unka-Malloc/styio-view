# ADR-0001: Frontend Runtime Uses Flutter

**Purpose:** 记录 `Vityo` 选择 Flutter 作为主前端运行时的背景、决策与后果。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

`Vityo` 需要：

1. 跨桌面、移动和 Web 的统一 UI 系统
2. 高自由度动画与现代界面表达
3. 非传统 IDE 控件导向的显示层
4. 不以 Chromium 壳为主路径

## Decision

选择 Flutter 作为主前端运行时和跨端 UI 框架。

## Alternatives

1. Qt：桌面文本编辑基础更强，但不符合当前对现代 UI 表达的主优先级。
2. Tauri / Electron：以 Web 技术壳为主，不符合当前方向。
3. Compose Multiplatform：可行，但现阶段与 `styio` 原生核心的桥接链路不如 Flutter + `FFI Adapter` 清晰。

## Consequences

1. UI 层获得高自由度渲染与动画能力。
2. 需要自研文本编辑核心，而不是依赖成熟桌面编辑控件。
3. 原生核心应通过 FFI 或等效桥接接入。
