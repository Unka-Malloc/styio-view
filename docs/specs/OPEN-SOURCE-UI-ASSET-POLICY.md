# Open Source UI Asset Policy

**Purpose:** 约束 `Vityo` 的默认字体、glyph 字体、主题标签和调色盘来源，降低商业专有资产与品牌命名带来的许可或争议风险。

**Last updated:** 2026-04-13

## 1. 默认要求

1. 默认界面字体、默认编辑器字体、默认数学 glyph 字体必须来自开源字体项目。
2. 不得把商业专有系统字体作为默认值或默认 fallback 的前几位。
3. 用户可见主题标签与调色盘标签优先使用中性命名，不直接使用第三方产品品牌名。
4. 若某套视觉方案只是借鉴公开调色思路，默认 UI 中应使用中性别名，而不是把原主题名直接暴露为主标签。

## 2. 当前允许的默认字体族

### 2.1 界面字体

1. `IBM Plex Sans`
2. `Inter`
3. `Noto Sans`
4. `Recursive`

### 2.2 编辑器等宽字体

1. `JetBrains Mono`
2. `IBM Plex Mono`
3. `Recursive`

### 2.3 数学 / glyph fallback

1. `STIX Two Math`
2. `Noto Sans Math`
3. `JetBrains Mono`
4. `IBM Plex Mono`
5. `Recursive`

## 3. 当前禁止作为默认值的字体

1. `Avenir Next`
2. `Helvetica Neue`
3. `Segoe UI`
4. `SF Mono`
5. `Menlo`
6. `Futura`
7. `Optima`
8. `Cambria Math`

## 4. 主题与调色盘命名策略

1. `Styio` 是第一方主题标签，可以保留。
2. 其它预设默认使用中性命名，例如：
   - `Studio Dark`
   - `Graphite Blue`
   - `Amber Night`
   - `Forge Dark`
   - `Plum Night`
   - `Arctic`
   - `Mocha`
   - `Solar`
3. 若内部需要兼容历史 key，可保留兼容映射；但用户可见标签应保持中性。

## 5. 审核要求

1. 新增字体前，先确认其官方许可允许分发、嵌入和软件打包。
2. 新增主题预设前，先确认来源可公开引用；若存在品牌或商标敏感性，改用中性标签。
3. 每次修改默认字体栈或默认主题集时，必须同步更新 `THIRD-PARTY.md`。

## 6. 当前核验来源

1. JetBrains Mono: 官方仓库许可文件
2. IBM Plex: 官方仓库许可文件
3. Inter: 官方仓库许可文件
4. Recursive: 官方仓库许可文件
5. Noto Fonts / Noto Sans Math: 官方仓库许可文件
6. STIX Fonts / STIX Two Math: 官方仓库许可文件
7. 主题与调色盘：用户可见名称已改为中性标签；内部色值仅作为功能性配置数据使用

## 7. 官方来源链接

1. JetBrains Mono: <https://github.com/JetBrains/JetBrainsMono>
2. IBM Plex: <https://github.com/IBM/plex>
3. Inter: <https://github.com/rsms/inter>
4. Recursive: <https://github.com/arrowtype/recursive>
5. Noto Fonts: <https://github.com/notofonts>
6. STIX Fonts: <https://github.com/stipub/stixfonts>
7. Dracula Theme: <https://github.com/dracula/dracula-theme>
8. Nord: <https://github.com/arcticicestudio/nord>
9. Catppuccin: <https://github.com/catppuccin/catppuccin>
10. Solarized: <https://github.com/altercation/solarized>
