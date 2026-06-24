# Theme / UX Runbook

**Purpose:** 提供 theme、视觉系统、样式层和 UX guardrail 的日常维护入口。

**Last updated:** 2026-06-24

## Mission

负责 theme system、字体与 palette 基线、样式层、布局系统和容器约束。该团队不拥有编辑行为语义或 adapter 合同本身，但负责确保这些能力在界面上以一致且可维护的方式呈现。

## Owned Surface

Primary paths:

1. `frontend/vityo_app/lib/src/view_render/theme/`
2. `frontend/vityo_app/lib/src/view_render/platform/`
3. `frontend/vityo_app/lib/src/theme/`
4. `frontend/vityo_app/lib/src/platform/viewport_profile.dart`
5. `prototype/styles.css`
6. `prototype/editor-styles/`
7. `prototype/theme-config.example.jsonc`
8. `docs/specs/UX-MAINTENANCE-GUIDELINES.md`
9. `docs/specs/OPEN-SOURCE-UI-ASSET-POLICY.md`
10. `docs/specs/STYIO-THEME-CONFIG.md`
11. `prototype/styio-*.html`

Key SSOTs:

1. `产品规格 -> ../design/Vityo-Product-Spec.md`
2. `UX 维护准则 -> ../specs/UX-MAINTENANCE-GUIDELINES.md`
3. `开源 UI 资产策略 -> ../specs/OPEN-SOURCE-UI-ASSET-POLICY.md`

## Daily Workflow

1. 改字体、palette、theme preset 或图标系统前，先确认默认方案满足开源与低争议来源约束。
2. 所有窄屏、侧栏、抽屉和弹窗变更，都要先检查内部组件是否溢出父容器。
3. 若同一视觉系统同时作用于 Flutter 主壳和手写原型，先明确 canonical token/source 在哪一边，再同步另一边。
4. 视觉变更不应绕过产品语义或 adapter 边界；必要时拉对应消费团队一起 review。
5. `VityoThemeOverride` 只冻结最小 theme token override、JSON round-trip 和 Material color binding；本轮不新增完整主题编辑器、远程 profile sync 或用户市场主题。
6. 默认 palette、font size、chip/button/card constraints 变化必须通过 Flutter widget tests 或明确的视觉验收说明确认，不把产品 gate 截图测试写成默认必过项。
7. `prototype/styio-*.html` 只作为 `style-experiment` 视觉参考存在；新增或删除这些页面时，必须同步 `prototype/prototype-manifest.json`，并且不得在样式实验里新增产品语义、workspace mutation 或 dev-server API 合同。
8. Flutter theme 和 viewport profile 的实现归 `view_render/theme` 与 `view_render/platform`；legacy `src/theme/` 和 `src/platform/viewport_profile.dart` 只能做兼容导出。
9. Theme persistence 和 prototype style 变更只能改变视觉 token、布局约束或呈现状态；不得在 `prototype/styles.css` 或 theme façade 中塞入编辑、runtime、agent 或 workspace 语义。

## Change Classes

1. Small: 局部 spacing、颜色、字体或样式整理。跑最小自测并检查容器约束。
2. Medium: palette 结构、theme override JSON、theme 配置、layout strategy 或 editor style 系统变化。补 handbook 或 UX 文档。
3. High: 默认视觉基线、字体来源、主题系统分层或跨主线布局策略变化。走协调 review。

## Required Gates

Minimum:

```bash
cd prototype && npm run governance
cd prototype && npm run selftest:editor
cd frontend/vityo_app && flutter analyze && flutter test
```

## Cross-Team Dependencies

1. Shell / Editor 必须 review 影响编辑器层级、focused editor 或 language inspector 的视觉变更。
2. Runtime / Agent 必须 review 影响 runtime/debug/agent panel 结构的视觉变更。
3. Docs / Delivery 必须 review UX 文档、handbook 或视觉基线记录更新。
4. Module / Platform 必须 review 平台 profile 或 capability 展示层变化。

## Handoff / Recovery

Record:

1. 变更影响的是 Flutter、handwritten web，还是两条线同时。
2. 受影响的字体、palette、preset 或 layout token。
3. 已核对的容器约束与窄屏场景。
4. 仍需消费团队确认的视觉差异点。
