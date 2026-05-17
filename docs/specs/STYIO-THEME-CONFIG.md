# Styio Theme Config

**Purpose:** 定义 `Vityo` 原型当前支持的主题 / 编辑器调色盘配置文件格式，结构参考 VS Code 的 `settings.json`、`workbench.colorCustomizations` 和 `editor.tokenColorCustomizations`。

**Last updated:** 2026-04-21

## 1. 结构

```jsonc
{
  "$schema": "https://styio.dev/schemas/theme-customizations.json",
  "name": "Custom Palette",
  "workbench.colorCustomizations": {},
  "editor": {},
  "styioView": {},
  "editor.tokenColorCustomizations": {}
}
```

## 2. 支持字段

### 2.1 `workbench.colorCustomizations`

1. `styio.themeColor`
2. `styio.themePalette`
3. `styio.themeText`
4. `styio.background`
5. `styio.themeLines`
6. `styio.interfaceFont`
7. `styio.interfaceSize`

这些字段当前接受预设 key / 标签名；默认字体预设命名为 `Default ...`，例如 `defaultSans`，默认金色高亮显示为 `Gold`，其 key 仍为 `defaultGold`。`styio.interfaceSize` 也支持实际字号数字，例如 `13..17`。

### 2.2 `editor`

1. `tabSize`
2. `fontFamily`
3. `fontSize`

`tabSize` 当前只接受 `2` 或 `4`。  
`fontFamily` 当前优先按已知预设 key / label 匹配。  
`fontSize` 支持实际字号数字，当前支持 `13..17` 这 5 档。

### 2.3 `styioView`

1. `style`
2. `language`
3. `glyphComposition`
4. `themeMode`
5. `editorMode`
6. `visualTokens`

`style` 当前支持：

1. `grid`
2. `editorial`

默认值当前为 `grid`。

`language` 当前支持：

1. `zhCn`
2. `en`

`visualTokens` 是一层“最终视觉覆盖”，会在 preset 应用完成后最后生效，因此优先级高于 `Theme / Editor / Style` 预设本身。当前支持的 group 包括：

1. `title`
2. `accent`
3. `text`
4. `radius`
5. `border`
6. `shadow`
7. `surface`
8. `font`
9. `editor`
10. `settings`

典型例子：

1. `title.color`
2. `title.fontSize`
3. `radius.ui`
4. `border.width`
5. `border.color`
6. `shadow.card`
7. `font.ui.family`
8. `font.ui.size`
9. `font.editor.family`
10. `font.editor.size`
11. `editor.background`
12. `editor.selection`
13. `settings.titleSize`

未知字段会被忽略，不会报错。

### 2.4 `editor.tokenColorCustomizations`

1. `styio.palette`
2. `styio.editorBackground`
3. `styio.textColor`
4. `styio.textHighlight`
5. `styio.block`
6. `styio.line`
7. `styio.selection`
8. `styio.symbolColors`

`styio.symbolColors` 接受 glyph key 或 token 作为字段名，例如：

1. `#`
2. `@`
3. `>_`
4. `|>`
5. `<|`
6. `->`
7. `<-`
8. `=>`
9. `<=`
10. `:=`

值当前接受 hex 颜色。

## 3. 导入逻辑

1. 文件扩展名不做限制。
2. 解析器支持 JSONC 风格注释与尾随逗号。
3. 只有在解析失败或字段不合法时才报错。

## 4. 存放逻辑

当前手写 Web prototype 采用“用户设置”思路：

1. 导入或编辑后的配置会被归一化成一份 canonical JSON 配置
2. 配置保存在浏览器本地存储中
3. 当前 localStorage key 为 `Vityo:custom-palette-config`
4. 普通 UI 设置改动会同步回这份 canonical 配置

如果存在 `styioView.visualTokens`，这些 token 也会被持久化进同一份 canonical 配置。

这和 VS Code 的“设置文件驱动 UI 状态”思路保持一致；后续若引入 workspace-scoped 配置，再扩展到工作区级文件。

## 5. 导入 / 编辑行为

1. `Import Config` 会复用 `Open Workspace` 那套浏览器，但切换到“选文件”模式
2. 文件扩展名不做限制，只要能读成文本就尝试解析
3. 解析失败时，错误会直接回写到 picker / dialog，不会默默吞掉
4. `Edit` 会打开当前 canonical 配置文本，保存后立即应用到页面

## 6. 示例

可直接参考：

1. [theme-config.example.jsonc](../../prototype/theme-config.example.jsonc)
