# ADR-0002: Native Bridge Is Exposed As FFI Adapter

**Purpose:** 记录 `Vityo` 如何把上游 `styio` 原生核心接入 Flutter。

**Last updated:** 2026-04-12

**Status:** Accepted

**Date:** 2026-04-12

## Context

上游 `styio` 是 C++20 + LLVM 的编译器与运行时核心，而 Flutter 侧需要稳定、可维护、可跨平台的接入方式。

## Decision

原生接入统一只使用 `FFI Adapter` 这个产品术语。实现上可以是稳定 C ABI、sidecar native bridge 或其它原生形式，但对 `Vityo` 主线而言只暴露成 `FFI Adapter`。

## Alternatives

1. 直接绑定 C++ ABI：跨平台不稳定，维护成本高。
2. 先走 HTTP / 本地服务：增加系统复杂度，不适合首发本地桌面闭环。
3. 仅通过 CLI 子进程通信：首发可以局部使用，但不足以支撑长期深度集成。

## Consequences

1. Flutter 与上游内部 C++ ABI 解耦。
2. 主线不再引入特定命名的 native bridge 包概念。
3. 需要额外维护所有权、内存释放与错误协议。
