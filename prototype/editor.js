import {
  workspaceApiBase,
  primaryFile,
  defaultCreateLeafNames,
  fallbackSources,
  storageKeys,
  customPaletteConfigSchema,
  createInitialRuntimeState,
} from "./editor-modules/runtime-config.js";
import { autoSaveModeOptionsList, languageOptionsList, SURFACE_KEYS } from "./editor-modules/enums.js";
import {
  SURFACE_ACTIONS,
  SURFACE_PERSIST_TARGETS,
  SURFACE_RENDER_TARGETS,
} from "./editor-modules/surface-actions.js";
import {
  themeColorPresets,
  themeBackgroundPresets,
  themeTextPresets,
  themeLinePresets,
  themePalettePresets,
  interfaceFontOptionsList,
  interfaceSizeOptionsList,
  editorFontOptionsList,
  editorFontSizePresets,
  legacyInterfaceSizeKeyMap,
  legacyThemeColorKeyMap,
  legacyInterfaceFontKeyMap,
  legacyEditorFontKeyMap,
  legacyEditorFontSizeKeyMap,
  legacyEditorTextHighlightKeyMap,
  legacyDefaultGlyphPaletteKeyMap,
  editorBackgroundPresets,
  editorTextColorPresets,
  editorTextHighlightPresets,
} from "./editor-modules/theme-presets.js";
import {
  operatorGlyphs,
  glyphOperators,
  glyphOperatorPattern,
  glyphColorSpecs,
  glyphColorOptions,
  glyphPaletteOptions,
  editorPaletteMeta,
  legacyGlyphPaletteKeyMap,
  blockSurfacePresets,
  lineHighlightPresets,
  selectionHighlightPresets,
  defaultGlyphColor,
} from "./editor-modules/glyph-presets.js";
import { styioKeywordTokens } from "./editor-modules/styio-language-config.js";
import { createRenderPipeline, RenderSlice } from "./editor-modules/render-pipeline.js";
import { settingsCardsSchema } from "./editor-modules/settings-schema.js";
import { createCardFactory, createSettingsNodes } from "./editor-modules/settings-factory.js";
import { settingsFactoryTokens, serializeSettingsFactoryTokens } from "./editor-modules/settings-tokens.js";
import { createUiStyleFactory, uiStyleOptionsList } from "./editor-modules/style-strategies.js?v=20260414-editorial-block-contrast";
import {
  applyStyleShellLabels,
  bindStyleShellBridgeEvents,
  createStyleShellBridge,
  syncStyleShellLayout,
  syncStyleShellTitles,
} from "./editor-modules/common/style-shell-bridge.js";
import {
  bindGridLayoutConfigTarget,
  installGridLayoutConfigDebugApi,
} from "./editor-modules/grid-style/layout-config-store.js";
import {
  applyVisualTokenOverrides,
  buildVisualTokenConfigObject,
  hasVisualTokenOverrides,
  normalizeVisualTokenOverrides,
} from "./editor-modules/visual-token-config.js";

const legacyUiStyleKeyMap = Object.freeze({
  carbon: "editorial",
});

const workspaceShell = document.getElementById("workspaceShell");
const styleShellBridge = createStyleShellBridge(document);
const {
  gridRefs: { fileTabs },
} = styleShellBridge;
const drawerTabs = Array.from(document.querySelectorAll("[data-drawer-tab]"));
const settingsFactoryRoot = document.getElementById("settingsFactoryRoot");
const fileTree = document.getElementById("fileTree");
const saveState = document.getElementById("saveState");
const autoSaveState = document.getElementById("autoSaveState");
const glyphState = document.getElementById("glyphState");
const indentState = document.getElementById("indentState");
const unitState = document.getElementById("unitState");
const cursorState = document.getElementById("cursorState");
const issueState = document.getElementById("issueState");
const renderState = document.getElementById("renderState");
const workspacePathHint = document.getElementById("workspacePathHint");
const workspaceTitle = document.getElementById("workspaceTitle");
const workspacePathDisplay = document.getElementById("workspacePathDisplay");
const workspacePathViewport = document.getElementById("workspacePathViewport");
const workspacePathTrack = document.getElementById("workspacePathTrack");
const workspacePathScrollVisual = document.getElementById("workspacePathScrollVisual");
const workspacePathScrollThumb = document.getElementById("workspacePathScrollThumb");
const workspacePathText = document.getElementById("workspacePathText");
const workspacePathApply = document.getElementById("workspacePathApply");
const createFolderButton = document.getElementById("createFolderButton");
const quickCreateFileButton = document.getElementById("quickCreateFileButton");
const refreshWorkspaceButton = document.getElementById("refreshWorkspaceButton");
const bulkDeleteButton = document.getElementById("bulkDeleteButton");
const workspaceMoreButton = document.getElementById("workspaceMoreButton");
const workspaceCallout = document.getElementById("workspaceCallout");
const workspaceCalloutTitle = document.getElementById("workspaceCalloutTitle");
const workspaceCalloutBody = document.getElementById("workspaceCalloutBody");
const workspaceCalloutOpen = document.getElementById("workspaceCalloutOpen");
const workspacePickerOverlay = document.getElementById("workspacePickerOverlay");
const workspacePickerClose = document.getElementById("workspacePickerClose");
const workspacePickerTitle = document.getElementById("workspacePickerTitle");
const workspacePickerCaption = document.getElementById("workspacePickerCaption");
const workspacePickerUp = document.getElementById("workspacePickerUp");
const workspacePickerCurrent = document.getElementById("workspacePickerCurrent");
const workspacePickerBreadcrumbs = document.getElementById("workspacePickerBreadcrumbs");
const workspacePickerList = document.getElementById("workspacePickerList");
const workspacePickerConfirm = document.getElementById("workspacePickerConfirm");
const appToast = document.getElementById("appToast");
const appToastText = document.getElementById("appToastText");
const appDialogOverlay = document.getElementById("appDialogOverlay");
const appDialogClose = document.getElementById("appDialogClose");
const appDialogTitle = document.getElementById("appDialogTitle");
const appDialogMessage = document.getElementById("appDialogMessage");
const appDialogInputField = document.getElementById("appDialogInputField");
const appDialogInput = document.getElementById("appDialogInput");
const appDialogTextareaField = document.getElementById("appDialogTextareaField");
const appDialogTextarea = document.getElementById("appDialogTextarea");
const appDialogList = document.getElementById("appDialogList");
const appDialogCancel = document.getElementById("appDialogCancel");
const appDialogConfirm = document.getElementById("appDialogConfirm");
let detachGridLayoutConfigBinding = null;

if (settingsFactoryRoot) {
  const initialUiStyleFactory = createUiStyleFactory(createInitialRuntimeState().activeUiStyleKey, settingsFactoryTokens);
  const settingsFactory = createCardFactory({
    nodes: settingsCardsSchema,
    tokens: initialUiStyleFactory.settingsTokens,
  });
  settingsFactoryRoot.setAttribute("style", settingsFactory.style);
  settingsFactoryRoot.innerHTML = settingsFactory.markup;
}

function flattenSettingsNodes(nodes, acc = []) {
  for (const node of nodes ?? []) {
    if (!node) {
      continue;
    }
    acc.push(node);
    if (node.headAccessory) {
      flattenSettingsNodes([node.headAccessory], acc);
    }
    if (node.themeChildren?.length) {
      flattenSettingsNodes(node.themeChildren, acc);
    }
    if (node.editorChildren?.length) {
      flattenSettingsNodes(node.editorChildren, acc);
    }
    if (node.children?.length) {
      flattenSettingsNodes(node.children, acc);
    }
  }
  return acc;
}

const flatSettingsNodes = flattenSettingsNodes(settingsCardsSchema);
const settingsNodesById = new Map(flatSettingsNodes.map((node) => [node.id, node]));
const settingsDropdownNodesByButtonId = new Map(
  flatSettingsNodes
    .filter((node) => node.kind === "dropdown" && node.buttonId)
    .map((node) => [node.buttonId, node]),
);
const settingsDropdownNodesByOptionsId = new Map(
  flatSettingsNodes
    .filter((node) => node.kind === "dropdown" && node.optionsId)
    .map((node) => [node.optionsId, node]),
);
const settingsDialogActionsById = new Map(
  flatSettingsNodes.flatMap((node) =>
    (node.dialogSpec?.actions ?? []).map((action) => [
      action.id,
      {
        node,
        action,
      },
    ]),
  ),
);

const toggleGlyphs = document.getElementById("toggleGlyphs");
const languageTitle = document.getElementById("languageTitle");
const styleTitle = document.getElementById("styleTitle");
const indentControl = document.getElementById("indentControl");
const saveFile = document.getElementById("saveFile");
const autoSaveTitle = document.getElementById("autoSaveTitle");
const themeTitle = document.getElementById("themeTitle");
const themeModeTitle = document.getElementById("themeModeTitle");
const themeColorCardTitle = document.getElementById("themeColorCardTitle");
const themeFontCardTitle = document.getElementById("themeFontCardTitle");
const themeConfigTitle = document.getElementById("themeConfigTitle");
const themePaletteTitle = document.getElementById("themePaletteTitle");
const themeTextTitle = document.getElementById("themeTextTitle");
const themeColorTitle = document.getElementById("themeColorTitle");
const themeBackgroundTitle = document.getElementById("themeBackgroundTitle");
const themeLineTitle = document.getElementById("themeLineTitle");
const interfaceFontTitle = document.getElementById("interfaceFontTitle");
const interfaceSizeTitle = document.getElementById("interfaceSizeTitle");
const editorTitle = document.getElementById("editorTitle");
const editorFontCardTitle = document.getElementById("editorFontCardTitle");
const editorColorCardTitle = document.getElementById("editorColorCardTitle");
const editorConfigTitle = document.getElementById("editorConfigTitle");
const tabSizeTitle = document.getElementById("tabSizeTitle");
const editorFontTitle = document.getElementById("editorFontTitle");
const editorFontSizeTitle = document.getElementById("editorFontSizeTitle");
const editorPaletteTitle = document.getElementById("editorPaletteTitle");
const editorBackgroundTitle = document.getElementById("editorBackgroundTitle");
const textColorTitle = document.getElementById("textColorTitle");
const textHighlightTitle = document.getElementById("textHighlightTitle");
const blockTitle = document.getElementById("blockTitle");
const lineTitle = document.getElementById("lineTitle");
const selectionTitle = document.getElementById("selectionTitle");
const linkedSurfaceModeTitle = document.getElementById("linkedSurfaceModeTitle");
const linkedSurfaceThemeTab = document.getElementById("linkedSurfaceThemeTab");
const linkedSurfaceEditorTab = document.getElementById("linkedSurfaceEditorTab");
const linkedSurfaceThemePanel = document.getElementById("linkedSurfaceThemePanel");
const linkedSurfaceEditorPanel = document.getElementById("linkedSurfaceEditorPanel");
const linkedEditorModeLinkButton = document.getElementById("linkedEditorModeLinkButton");
const linkedSurfaceModeToggle = document.getElementById("linkedSurfaceModeToggle");
const linkedSurfaceModeDark = document.getElementById("linkedSurfaceModeDark");
const linkedSurfaceModeLight = document.getElementById("linkedSurfaceModeLight");
const importThemeConfigButton = document.getElementById("importThemeConfigButton");
const editThemeConfigButton = document.getElementById("editThemeConfigButton");
const importEditorConfigButton = document.getElementById("importEditorConfigButton");
const editEditorConfigButton = document.getElementById("editEditorConfigButton");
const languageModeButton = document.getElementById("languageModeButton");
const languageModeOptions = document.getElementById("languageModeOptions");
const styleButton = document.getElementById("styleButton");
const styleOptions = document.getElementById("styleOptions");
const autoSaveModeButton = document.getElementById("autoSaveModeButton");
const autoSaveModeOptions = document.getElementById("autoSaveModeOptions");
const autoSaveDelayField = document.getElementById("autoSaveDelayField");
const autoSaveDelayInput = document.getElementById("autoSaveDelayInput");
const autoSaveDelayLabel = document.getElementById("autoSaveDelayLabel");
const themeModeToggle = document.getElementById("themeModeToggle");
const themeModeDark = document.getElementById("themeModeDark");
const themeModeLight = document.getElementById("themeModeLight");
const themePaletteButton = document.getElementById("themePaletteButton");
const themePaletteOptionsMenu = document.getElementById("themePaletteOptions");
const themeTextButton = document.getElementById("themeTextButton");
const themeTextOptions = document.getElementById("themeTextOptions");
const themeColorButton = document.getElementById("themeColorButton");
const themeColorOptions = document.getElementById("themeColorOptions");
const themeBackgroundButton = document.getElementById("themeBackgroundButton");
const themeBackgroundOptions = document.getElementById("themeBackgroundOptions");
const themeLineButton = document.getElementById("themeLineButton");
const themeLineOptions = document.getElementById("themeLineOptions");
const interfaceFontButton = document.getElementById("interfaceFontButton");
const interfaceFontOptions = document.getElementById("interfaceFontOptions");
const interfaceSizeControl = document.getElementById("interfaceSizeControl");
const interfaceSizeDecrease = document.getElementById("interfaceSizeDecrease");
const interfaceSizeIncrease = document.getElementById("interfaceSizeIncrease");
const interfaceSizeValue = document.getElementById("interfaceSizeValue");
const glyphCompositionTitle = document.getElementById("glyphCompositionTitle");
const editorFontButton = document.getElementById("editorFontButton");
const editorFontOptions = document.getElementById("editorFontOptions");
const editorFontSizeControl = document.getElementById("editorFontSizeControl");
const editorFontSizeDecrease = document.getElementById("editorFontSizeDecrease");
const editorFontSizeIncrease = document.getElementById("editorFontSizeIncrease");
const editorFontSizeValue = document.getElementById("editorFontSizeValue");
const editorModeToggle = document.getElementById("editorModeToggle");
const editorModeDark = document.getElementById("editorModeDark");
const editorModeLight = document.getElementById("editorModeLight");
const highlightPaletteButton = document.getElementById("highlightPaletteButton");
const highlightPaletteOptions = document.getElementById("highlightPaletteOptions");
const editorBackgroundButton = document.getElementById("editorBackgroundButton");
const editorBackgroundOptions = document.getElementById("editorBackgroundOptions");
const textColorButton = document.getElementById("textColorButton");
const textColorOptions = document.getElementById("textColorOptions");
const textHighlightButton = document.getElementById("textHighlightButton");
const textHighlightOptions = document.getElementById("textHighlightOptions");
const blockSurfaceButton = document.getElementById("blockSurfaceButton");
const blockSurfaceOptions = document.getElementById("blockSurfaceOptions");
const lineHighlightButton = document.getElementById("lineHighlightButton");
const lineHighlightOptions = document.getElementById("lineHighlightOptions");
const selectionHighlightButton = document.getElementById("selectionHighlightButton");
const selectionHighlightOptions = document.getElementById("selectionHighlightOptions");
const symbolColorsTitle = document.getElementById("symbolColorsTitle");
const glyphColorList = document.getElementById("glyphColorList");
const lineGutter = document.getElementById("lineGutter");
const codeStage = document.getElementById("codeStage");
const blockLayer = document.getElementById("blockLayer");
const renderLayer = document.getElementById("renderLayer");
const caretLayer = document.getElementById("caretLayer");
const caretIndicator = document.getElementById("caretIndicator");
const editorInput = document.getElementById("editorInput");

const initialRuntimeState = createInitialRuntimeState();
const fileSources = { ...fallbackSources };
const fileDirty = {};
let fileOrder = [...initialRuntimeState.fileOrder];
let currentFile = initialRuntimeState.currentFile;
let glyphsOn = initialRuntimeState.glyphsOn;
let workspaceApiAvailable = initialRuntimeState.workspaceApiAvailable;
let workspaceRootPath = initialRuntimeState.workspaceRootPath;
let workspaceName = initialRuntimeState.workspaceName;
let workspaceEntries = [...initialRuntimeState.workspaceEntries];
let workspaceFiles = [...initialRuntimeState.workspaceFiles];
let workspaceLoadedFiles = initialRuntimeState.workspaceLoadedFiles;
let saveInFlight = initialRuntimeState.saveInFlight;
let latestAnalysis = initialRuntimeState.latestAnalysis;
let sidebarOpen = initialRuntimeState.sidebarOpen;
let activeDrawerTab = initialRuntimeState.activeDrawerTab;
let linkedSurfaceActiveTab = initialRuntimeState.linkedSurfaceActiveTab;
let editorModeLinkedToTheme = initialRuntimeState.editorModeLinkedToTheme;
let indentSize = initialRuntimeState.indentSize;
let activeLanguageKey = initialRuntimeState.activeLanguageKey;
let languageMenuOpen = initialRuntimeState.languageMenuOpen;
let activeUiStyleKey = initialRuntimeState.activeUiStyleKey;
let styleMenuOpen = initialRuntimeState.styleMenuOpen;
let autoSaveMode = initialRuntimeState.autoSaveMode;
let autoSaveDelay = initialRuntimeState.autoSaveDelay;
let autoSaveMenuOpen = initialRuntimeState.autoSaveMenuOpen;
let autoSaveTimer = null;
let themeMode = initialRuntimeState.themeMode;
let themePaletteMenuOpen = initialRuntimeState.themePaletteMenuOpen;
let themeColorMenuOpen = initialRuntimeState.themeColorMenuOpen;
let themeBackgroundMenuOpen = initialRuntimeState.themeBackgroundMenuOpen;
let interfaceFontMenuOpen = initialRuntimeState.interfaceFontMenuOpen;
let themeTextMenuOpen = initialRuntimeState.themeTextMenuOpen;
let themeLineMenuOpen = initialRuntimeState.themeLineMenuOpen;
let editorFontMenuOpen = initialRuntimeState.editorFontMenuOpen;
let openGlyphColorMenu = initialRuntimeState.openGlyphColorMenu;
let paletteMenuOpen = initialRuntimeState.paletteMenuOpen;
let editorBackgroundMenuOpen = initialRuntimeState.editorBackgroundMenuOpen;
let textColorMenuOpen = initialRuntimeState.textColorMenuOpen;
let textHighlightMenuOpen = initialRuntimeState.textHighlightMenuOpen;
let blockSurfaceMenuOpen = initialRuntimeState.blockSurfaceMenuOpen;
let lineHighlightMenuOpen = initialRuntimeState.lineHighlightMenuOpen;
let selectionHighlightMenuOpen = initialRuntimeState.selectionHighlightMenuOpen;
let editorMode = initialRuntimeState.editorMode;
let activeThemePaletteKey = initialRuntimeState.activeThemePaletteKey;
let activeThemeColorKey = initialRuntimeState.activeThemeColorKey;
let activeThemeBackgroundKey = initialRuntimeState.activeThemeBackgroundKey;
let activeThemeTextKey = initialRuntimeState.activeThemeTextKey;
let activeInterfaceFontKey = initialRuntimeState.activeInterfaceFontKey;
let activeInterfaceSizeKey = initialRuntimeState.activeInterfaceSizeKey;
let activeEditorFontKey = initialRuntimeState.activeEditorFontKey;
let activeEditorFontSizeKey = initialRuntimeState.activeEditorFontSizeKey;
let activePaletteKey = initialRuntimeState.activePaletteKey;
let activeEditorBackgroundKey = initialRuntimeState.activeEditorBackgroundKey;
let activeEditorTextColorKey = initialRuntimeState.activeEditorTextColorKey;
let activeEditorTextHighlightKey = initialRuntimeState.activeEditorTextHighlightKey;
let activeThemeLineKey = initialRuntimeState.activeThemeLineKey;
let activeBlockSurfaceKey = initialRuntimeState.activeBlockSurfaceKey;
let activeLineHighlightKey = initialRuntimeState.activeLineHighlightKey;
let activeSelectionHighlightKey = initialRuntimeState.activeSelectionHighlightKey;
let visualTokenOverrides = { ...initialRuntimeState.visualTokenOverrides };
let pointerSelectionAnchor = null;
let pointerSelectionCleanup = null;
let pendingLayoutRenderTimeout = 0;
let latestAnalysisFile = "";
let latestAnalysisSource = "";
let workspacePickerPath = initialRuntimeState.workspacePickerPath;
let workspacePickerParentPath = initialRuntimeState.workspacePickerParentPath;
let workspacePickerMode = initialRuntimeState.workspacePickerMode;
let workspacePickerIncludeFiles = initialRuntimeState.workspacePickerIncludeFiles;
let workspacePickerSelectedFilePath = initialRuntimeState.workspacePickerSelectedFilePath;
let workspacePickerConfirmAction = initialRuntimeState.workspacePickerConfirmAction;
let workspacePickerTitleText = initialRuntimeState.workspacePickerTitleText;
let workspacePickerDefaultCaptionText = initialRuntimeState.workspacePickerDefaultCaptionText;
let workspacePickerConfirmText = initialRuntimeState.workspacePickerConfirmText;
let openFileActionMenu = initialRuntimeState.openFileActionMenu;
let pendingDeleteFile = initialRuntimeState.pendingDeleteFile;
let bulkDeleteMode = initialRuntimeState.bulkDeleteMode;
let selectedTreePaths = initialRuntimeState.selectedTreePaths;
let activeTreePath = initialRuntimeState.activeTreePath;
let expandedTreePaths = initialRuntimeState.expandedTreePaths;
let workspacePathDrag = null;
let activeDialogResolver = null;
let appToastTimer = null;
const {
  glyphHighlight: glyphHighlightStorageKey,
  autoSave: autoSaveStorageKey,
  language: languageStorageKey,
  themeSettings: themeSettingsStorageKey,
  editorSettings: editorSettingsStorageKey,
  customPaletteConfig: customPaletteConfigStorageKey,
} = storageKeys;

const renderGroups = Object.freeze({
  themeAppearance: [RenderSlice.themeAppearance],
  settingsState: [RenderSlice.settingsState],
  settingsControls: [RenderSlice.settingsControls, RenderSlice.settingsState],
  sidebar: [RenderSlice.sidebar],
  themeSurface: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  themeFont: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  themeColor: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorSurface: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorFont: [
    RenderSlice.themeAppearance,
    RenderSlice.settingsState,
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
    RenderSlice.statusbar,
  ],
  editorColor: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorBlock: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorLine: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorSelectionStyle: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorGlyph: [RenderSlice.themeAppearance, RenderSlice.settingsState],
  editorContent: [
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
    RenderSlice.statusbar,
    RenderSlice.saveUi,
  ],
  editorSelection: [RenderSlice.editorLines, RenderSlice.editorCaret, RenderSlice.statusbar],
  editorLayout: [
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
  ],
  editorTheme: [
    RenderSlice.themeAppearance,
    RenderSlice.settingsState,
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
    RenderSlice.statusbar,
  ],
  fullEditor: [
    RenderSlice.sidebar,
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
    RenderSlice.statusbar,
    RenderSlice.saveUi,
  ],
  fullApp: [
    RenderSlice.themeAppearance,
    RenderSlice.settingsControls,
    RenderSlice.sidebar,
    RenderSlice.editorLines,
    RenderSlice.editorLayout,
    RenderSlice.editorBlocks,
    RenderSlice.editorCaret,
    RenderSlice.statusbar,
    RenderSlice.saveUi,
  ],
});

const renderPipeline = createRenderPipeline({ flush: flushRenderSlices });
const surfaceRenderTargets = Object.freeze({
  [SURFACE_RENDER_TARGETS.THEME_SURFACE]: renderGroups.themeSurface,
  [SURFACE_RENDER_TARGETS.THEME_FONT]: renderGroups.themeFont,
  [SURFACE_RENDER_TARGETS.THEME_COLOR]: renderGroups.themeColor,
  [SURFACE_RENDER_TARGETS.EDITOR_SURFACE]: renderGroups.editorSurface,
  [SURFACE_RENDER_TARGETS.EDITOR_FONT]: renderGroups.editorFont,
  [SURFACE_RENDER_TARGETS.EDITOR_COLOR]: renderGroups.editorColor,
  [SURFACE_RENDER_TARGETS.EDITOR_BLOCK]: renderGroups.editorBlock,
  [SURFACE_RENDER_TARGETS.EDITOR_LINE]: renderGroups.editorLine,
  [SURFACE_RENDER_TARGETS.EDITOR_SELECTION]: renderGroups.editorSelectionStyle,
  [SURFACE_RENDER_TARGETS.EDITOR_GLYPH]: renderGroups.editorGlyph,
});

function hasRenderSlice(slices, slice) {
  return slices.has(slice);
}

function requestRender(...slices) {
  renderPipeline.request(...slices);
}

function flushRender(...slices) {
  renderPipeline.flushNow(...slices);
}

function getCurrentAnalysis() {
  const source = fileSources[currentFile] ?? "";
  if (latestAnalysis && latestAnalysisFile === currentFile && latestAnalysisSource === source) {
    return latestAnalysis;
  }

  latestAnalysis = analyzeSource(source);
  latestAnalysisFile = currentFile;
  latestAnalysisSource = source;
  return latestAnalysis;
}

function renderSidebarModule() {
  syncBulkDeleteButton();
  syncRefreshWorkspaceButton();
  renderFileTabs();
  renderFileTree();
}

function flushRenderSlices(requestedSlices) {
  if (hasRenderSlice(requestedSlices, RenderSlice.themeAppearance)) {
    applyWorkbenchThemeState();
    applyEditorFontTheme();
    applyEditorFontSizeTheme();
    applyEditorTheme();
    applyEditorBackgroundTheme();
    applyEditorTextColorTheme();
    applyEditorTextHighlightTheme();
    applyBlockSurfaceTheme();
    applyLineHighlightTheme();
    applySelectionHighlightTheme();
    applyGlyphColors();
    applyVisualTokenOverrides(visualTokenOverrides, {
      root: document.documentElement,
      settingsRoot: settingsFactoryRoot,
    });
  }

  if (hasRenderSlice(requestedSlices, RenderSlice.settingsControls)) {
    renderLanguageOptions();
    renderStyleOptions();
    renderAutoSaveOptions();
    renderThemeControls();
    renderEditorPreferenceControls();
    renderGlyphHighlightControls();
  } else if (hasRenderSlice(requestedSlices, RenderSlice.settingsState)) {
    syncSettingsUi();
  }

  if (hasRenderSlice(requestedSlices, RenderSlice.sidebar)) {
    renderSidebarModule();
  }

  const needsAnalysis =
    hasRenderSlice(requestedSlices, RenderSlice.editorLines) ||
    hasRenderSlice(requestedSlices, RenderSlice.editorLayout) ||
    hasRenderSlice(requestedSlices, RenderSlice.editorBlocks) ||
    hasRenderSlice(requestedSlices, RenderSlice.editorCaret) ||
    hasRenderSlice(requestedSlices, RenderSlice.statusbar);
  const analysis = needsAnalysis ? getCurrentAnalysis() : latestAnalysis;

  if (analysis && hasRenderSlice(requestedSlices, RenderSlice.editorLines)) {
    renderGutter(analysis);
    renderLines(analysis);
  }

  if (analysis && hasRenderSlice(requestedSlices, RenderSlice.editorLayout)) {
    syncOverlayMetrics();
    syncScroll();
  }

  if (analysis && hasRenderSlice(requestedSlices, RenderSlice.editorBlocks)) {
    renderBlocks(analysis);
  }

  if (analysis && hasRenderSlice(requestedSlices, RenderSlice.editorCaret)) {
    syncCaretIndicator(analysis);
  }

  if (analysis && hasRenderSlice(requestedSlices, RenderSlice.statusbar)) {
    updateStatusbar(analysis);
  }

  if (hasRenderSlice(requestedSlices, RenderSlice.saveUi)) {
    updateSaveUi();
  }
}

function requestSettingsStateRender() {
  requestRender(renderGroups.settingsState);
}

function requestSettingsControlsRender() {
  requestRender(renderGroups.settingsControls);
}

function requestSidebarRender() {
  requestRender(renderGroups.sidebar);
}

function requestEditorContentRender() {
  requestRender(renderGroups.editorContent);
}

function requestEditorSelectionRender() {
  requestRender(renderGroups.editorSelection);
}

function requestEditorThemeRender() {
  requestRender(renderGroups.editorTheme);
}

function flushFullAppRender() {
  flushRender(renderGroups.fullApp);
}

function persistEditorSurfaceState() {
  persistEditorPreferences();
  persistGlyphHighlights();
}

function persistSurfaceTarget(persistTarget) {
  if (persistTarget === SURFACE_PERSIST_TARGETS.THEME) {
    persistThemeSettings();
    return;
  }

  if (persistTarget === SURFACE_PERSIST_TARGETS.EDITOR) {
    persistEditorSurfaceState();
    return;
  }

  if (persistTarget === SURFACE_PERSIST_TARGETS.EDITOR_PREFERENCES) {
    persistEditorPreferences();
    return;
  }

  if (persistTarget === SURFACE_PERSIST_TARGETS.EDITOR_GLYPHS) {
    persistGlyphHighlights();
  }
}

function requestSurfaceRenderTarget(renderTarget) {
  const slices = surfaceRenderTargets[renderTarget];
  if (!slices) {
    requestEditorThemeRender();
    return;
  }
  requestRender(slices);
}

function dispatchSurfaceAction(action, applyState, options = {}) {
  if (!action || typeof applyState !== "function") {
    return;
  }

  const { closeMenus: shouldCloseMenus = true } = options;
  applyState();
  if (shouldCloseMenus) {
    closeSettingsMenus();
  }
  persistSurfaceTarget(action.persistTarget);
  requestSurfaceRenderTarget(action.renderTarget);
}

function themeSurfaceController() {
  return {
    getMode() {
      return themeMode;
    },
    setMode(nextMode) {
      themeMode = nextMode;
    },
    defaultPaletteForMode: defaultThemePaletteForMode,
    applyPaletteSelection: applyThemePaletteSelection,
  };
}

function editorSurfaceController() {
  return {
    getMode() {
      return editorMode;
    },
    setMode(nextMode) {
      editorMode = nextMode;
    },
    defaultPaletteForMode: defaultEditorPaletteForMode,
    applyPaletteSelection: applyEditorPaletteSelection,
  };
}

function getSurfaceController(surfaceKey) {
  if (surfaceKey === SURFACE_KEYS.THEME) {
    return themeSurfaceController();
  }
  if (surfaceKey === SURFACE_KEYS.EDITOR) {
    return editorSurfaceController();
  }
  throw new Error(`unknown surface controller: ${surfaceKey}`);
}

function syncEditorModeToThemeSurface({ persist = true, requestRender = true } = {}) {
  const controller = editorSurfaceController();
  controller.setMode(themeMode);
  const nextPalette = controller.defaultPaletteForMode(themeMode);
  if (nextPalette) {
    controller.applyPaletteSelection(nextPalette.key);
  }
  if (persist) {
    persistSurfaceTarget(SURFACE_PERSIST_TARGETS.EDITOR);
  }
  if (requestRender) {
    requestSurfaceRenderTarget(SURFACE_ACTIONS.EDITOR_MODE.renderTarget);
  }
}

function setEditorModeLinkState(nextLinked, { syncToTheme = nextLinked } = {}) {
  if (editorModeLinkedToTheme === nextLinked) {
    if (!nextLinked || !syncToTheme) {
      requestSettingsStateRender();
      return;
    }
  }

  editorModeLinkedToTheme = nextLinked;
  if (editorModeLinkedToTheme && syncToTheme) {
    syncEditorModeToThemeSurface();
    return;
  }
  requestSettingsStateRender();
}

function switchSurfaceMode(surfaceKey, nextMode) {
  if (surfaceKey === SURFACE_KEYS.EDITOR && editorModeLinkedToTheme) {
    requestSettingsStateRender();
    return;
  }

  const controller = getSurfaceController(surfaceKey);
  if (controller.getMode() === nextMode) {
    return;
  }

  const action =
    surfaceKey === SURFACE_KEYS.THEME ? SURFACE_ACTIONS.THEME_MODE : SURFACE_ACTIONS.EDITOR_MODE;
  dispatchSurfaceAction(action, () => {
    controller.setMode(nextMode);
    const nextPalette = controller.defaultPaletteForMode(controller.getMode());
    if (nextPalette) {
      controller.applyPaletteSelection(nextPalette.key);
    }
  });

  if (surfaceKey === SURFACE_KEYS.THEME && editorModeLinkedToTheme) {
    syncEditorModeToThemeSurface();
  }
}

function selectSurfacePalette(surfaceKey, paletteKey) {
  const controller = getSurfaceController(surfaceKey);
  const action =
    surfaceKey === SURFACE_KEYS.THEME ? SURFACE_ACTIONS.THEME_PALETTE : SURFACE_ACTIONS.EDITOR_PALETTE;
  dispatchSurfaceAction(action, () => {
    controller.applyPaletteSelection(paletteKey);
  });
}

const refreshWorkspaceSvg = `
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"></path>
    <path d="M21 3v5h-5"></path>
    <path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"></path>
    <path d="M8 16H3v5"></path>
  </svg>
`;
const cancelSelectionSvg = `
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M18 6 6 18"></path>
    <path d="m6 6 12 12"></path>
  </svg>
`;
function sidebarToggleSvg(isOpen) {
  return `
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="3" y="3" width="18" height="18" rx="2"></rect>
      <path d="M15 3v18"></path>
      ${
        isOpen
          ? '<path d="m8 9 3 3-3 3"></path>'
          : '<path d="m10 15-3-3 3-3"></path>'
      }
    </svg>
  `;
}
const translations = {
  zhCn: {
    documentTitle: "Styio 编辑器",
    appTitle: "styio",
    openSidebar: "打开侧边栏",
    closeSidebar: "关闭侧边栏",
    fileTree: "文件树",
    settings: "设置",
    workspace: "工作区",
    workspacePath: "工作区路径",
    open: "打开",
    workspaceActions: "工作区操作",
    createFolder: "创建文件夹",
    createFile: "创建文件",
    selectFilesToDelete: "选择要删除的文件",
    refreshWorkspace: "刷新工作区",
    moreWorkspaceActions: "更多工作区操作",
    language: "语言",
    style: "风格",
    autoSave: "自动保存",
    delay: "延迟",
    theme: "主题",
    color: "颜色",
    font: "字体",
    mode: "模式",
    themeConfig: "Config",
    customized: "Customized",
    linkEditorMode: "链接主题模式",
    unlinkEditorMode: "解除主题链接",
    themePalette: "预设",
    themeText: "文字",
    themeColor: "图标",
    background: "背景",
    lines: "边框",
    interfaceFont: "字体",
    interfaceSize: "字体大小",
    editor: "编辑器",
    glyphComposition: "符号组合渲染",
    tabSize: "Tab Size",
    editorFont: "字体",
    editorFontSize: "字体大小",
    palette: "预设",
    editorBackground: "背景",
    textColor: "文字",
    textHighlight: "关键词",
    block: "代码块高亮风格",
    line: "行高亮风格",
    selection: "选区高亮风格",
    symbolHighlight: "符号",
    usingBrowserStorage: "使用浏览器存储",
    usingBrowserStorageBody: "在你选择真实工作区文件夹之前，文件和编辑器设置会暂存在浏览器缓存中。",
    openWorkspace: "打开工作区",
    dialog: "对话框",
    closeDialog: "关闭对话框",
    closeWorkspacePicker: "关闭工作区选择器",
    openWorkspaceTitle: "打开工作区",
    chooseWorkspaceRoot: "选择一个本地文件夹作为当前工作区根目录。",
    goToParentFolder: "返回上级文件夹",
    useThisFolder: "使用此文件夹",
    importConfigFile: "导入配置文件",
    chooseConfigFile: "选择一个本地配置文件并导入当前配色设置。",
    importThisFile: "导入此文件",
    noFilesFound: "当前位置没有找到文件。",
    importConfig: "导入配置",
    editConfig: "编辑配置",
    configParseFailed: "配置解析失败",
    configImported: "配置已导入",
    configSaved: "配置已保存",
    themeConfigMessage: "编辑一份 JSONC 格式的主题配置。",
    noFilesInWorkspace: "当前工作区还没有文件。",
    previewFile: "预览文件",
    dirty: "未保存",
    deleteSinglePrompt: "删除这个工作区里的选中项？",
    deleteMultiplePrompt: "删除这个工作区里的 {count} 个选中项？",
    delete: "删除",
    cancel: "取消",
    confirm: "确认",
    renameFile: "重命名文件",
    rename: "重命名",
    renameFileMessage: "输入新的相对路径。",
    createFileTitle: "创建文件",
    createFileMessage: "输入当前工作区下的相对文件路径。",
    createFolderTitle: "创建文件夹",
    createFolderMessage: "输入当前工作区下的相对文件夹路径。",
    noDirectoriesFound: "当前位置没有找到目录。",
    loadingFolders: "正在加载文件夹…",
    deleteActiveEntry: "删除 {name}",
    deleteSelectedItems: "删除 {count} 个选中项",
    exitDeleteSelection: "退出多选删除",
    cancelMultiSelect: "取消多选",
    enableGlyphRendering: "启用符号渲染",
    disableGlyphRendering: "关闭符号渲染",
    lineSelection: "选区",
    diagnostics: "诊断",
    projection: "投影",
    diskLoading: "磁盘：加载中",
    autosaveLoading: "自动保存：加载中",
    glyphsLoading: "符号：加载中",
    indentLoading: "缩进：加载中",
    unitLoading: "单元：加载中",
  },
  en: {
    documentTitle: "Styio Editor",
    appTitle: "styio",
    openSidebar: "Open sidebar",
    closeSidebar: "Close sidebar",
    fileTree: "File tree",
    settings: "Settings",
    workspace: "Workspace",
    workspacePath: "Workspace path",
    open: "Open",
    workspaceActions: "Workspace actions",
    createFolder: "Create folder",
    createFile: "Create file",
    selectFilesToDelete: "Select files to delete",
    refreshWorkspace: "Refresh workspace",
    moreWorkspaceActions: "More workspace actions",
    language: "Language",
    style: "Style",
    autoSave: "Auto Save",
    delay: "Delay",
    theme: "Theme",
    color: "Color",
    font: "Font",
    mode: "Mode",
    themeConfig: "Config",
    customized: "Customized",
    linkEditorMode: "Link editor mode to theme",
    unlinkEditorMode: "Unlink editor mode",
    themePalette: "Palette",
    themeText: "Text",
    themeColor: "Icon",
    background: "Background",
    lines: "Lines",
    interfaceFont: "Font",
    interfaceSize: "Font Size",
    editor: "Editor",
    glyphComposition: "Glyph Composition",
    tabSize: "Tab Size",
    editorFont: "Font",
    editorFontSize: "Font Size",
    palette: "Palette",
    editorBackground: "Background",
    textColor: "Text",
    textHighlight: "Keyword",
    block: "Block",
    line: "Line",
    selection: "Selection",
    symbolHighlight: "Symbols",
    usingBrowserStorage: "Using Browser Storage",
    usingBrowserStorageBody:
      "Files and editor settings are currently staying in browser cache until you choose a real workspace folder.",
    openWorkspace: "Open Workspace",
    dialog: "Dialog",
    closeDialog: "Close dialog",
    closeWorkspacePicker: "Close workspace picker",
    openWorkspaceTitle: "Open Workspace",
    chooseWorkspaceRoot: "Choose a local folder to use as the current workspace root.",
    goToParentFolder: "Go to parent folder",
    useThisFolder: "Use This Folder",
    importConfigFile: "Import Config File",
    chooseConfigFile: "Choose a local config file to import the current palette settings.",
    importThisFile: "Import This File",
    noFilesFound: "No files found here.",
    importConfig: "Import Config",
    editConfig: "Edit",
    configParseFailed: "Config parse failed",
    configImported: "Config imported",
    configSaved: "Config saved",
    themeConfigMessage: "Edit a JSONC theme configuration.",
    noFilesInWorkspace: "No files in this workspace yet.",
    previewFile: "Preview file",
    dirty: "dirty",
    deleteSinglePrompt: "Delete the selected item from this workspace?",
    deleteMultiplePrompt: "Delete {count} selected items from this workspace?",
    delete: "Delete",
    cancel: "Cancel",
    confirm: "Confirm",
    renameFile: "Rename File",
    rename: "Rename",
    renameFileMessage: "Enter the new relative path.",
    createFileTitle: "Create File",
    createFileMessage: "Enter a relative path under the current workspace.",
    createFolderTitle: "Create Folder",
    createFolderMessage: "Enter a relative folder path under the current workspace.",
    noDirectoriesFound: "No directories found in this location.",
    loadingFolders: "Loading folders…",
    deleteActiveEntry: "Delete {name}",
    deleteSelectedItems: "Delete {count} selected item{suffix}",
    exitDeleteSelection: "Exit delete selection",
    cancelMultiSelect: "Cancel multi-select",
    enableGlyphRendering: "Enable glyph rendering",
    disableGlyphRendering: "Disable glyph rendering",
    lineSelection: "selection",
    diagnostics: "diagnostics",
    projection: "projection",
    diskLoading: "disk: loading",
    autosaveLoading: "autosave: loading",
    glyphsLoading: "glyphs: loading",
    indentLoading: "indent: loading",
    unitLoading: "unit: loading",
  },
};

let glyphColors = Object.fromEntries(glyphColorSpecs.map((spec) => [spec.key, defaultGlyphColor]));
const styioHighlightKeywords = new Set(styioKeywordTokens);

const measureLine = document.createElement("div");
measureLine.className = "measure-line";
document.body.appendChild(measureLine);

function getCssNumber(name) {
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue(name));
}

function t(key, params = {}) {
  const table = translations[activeLanguageKey] ?? translations.en;
  let value = table[key] ?? translations.en[key] ?? key;
  Object.entries(params).forEach(([name, replacement]) => {
    value = value.replaceAll(`{${name}}`, String(replacement));
  });
  return value;
}

function persistLanguageState() {
  try {
    window.localStorage.setItem(languageStorageKey, activeLanguageKey);
  } catch (error) {
    console.warn("failed to persist language state", error);
  }
  persistCustomPaletteConfigState();
}

function loadLanguageState() {
  try {
    const raw = window.localStorage.getItem(languageStorageKey);
    if (languageOptionsList.some((option) => option.key === raw)) {
      activeLanguageKey = raw;
    }
  } catch (error) {
    console.warn("failed to restore language state", error);
  }
}

function applyLanguageUi() {
  document.documentElement.lang = activeLanguageKey === "zhCn" ? "zh-CN" : "en";
  document.title = t("documentTitle");
  applyStyleShellLabels(styleShellBridge, t);

  document.querySelector('[data-drawer-tab="files"]')?.setAttribute("aria-label", t("fileTree"));
  document.querySelector('[data-drawer-tab="files"]')?.setAttribute("title", t("fileTree"));
  document.querySelector('[data-drawer-tab="settings"]')?.setAttribute("aria-label", t("settings"));
  document.querySelector('[data-drawer-tab="settings"]')?.setAttribute("title", t("settings"));

  workspaceTitle.textContent = t("workspace");
  workspacePathDisplay?.setAttribute("aria-label", t("workspacePath"));
  workspacePathApply.setAttribute("aria-label", t("openWorkspace"));
  workspacePathApply.setAttribute("title", t("openWorkspace"));
  document.querySelector(".workspace-action-row")?.setAttribute("aria-label", t("workspaceActions"));
  createFolderButton.setAttribute("aria-label", t("createFolder"));
  createFolderButton.setAttribute("title", t("createFolder"));
  quickCreateFileButton.setAttribute("aria-label", t("createFile"));
  quickCreateFileButton.setAttribute("title", t("createFile"));
  workspaceMoreButton.setAttribute("aria-label", t("moreWorkspaceActions"));
  workspaceMoreButton.setAttribute("title", t("moreWorkspaceActions"));

  languageTitle.textContent = t("language");
  if (styleTitle) {
    styleTitle.textContent = t("style");
  }
  autoSaveTitle.textContent = t("autoSave");
  autoSaveDelayLabel.textContent = t("delay");
  if (themeTitle) {
    themeTitle.textContent = t("theme");
  }
  if (themeColorCardTitle) {
    themeColorCardTitle.textContent = t("color");
  }
  if (themeFontCardTitle) {
    themeFontCardTitle.textContent = t("font");
  }
  if (themeConfigTitle) {
    themeConfigTitle.textContent = t("themeConfig");
  }
  if (themeModeTitle) {
    themeModeTitle.textContent = t("mode");
  }
  themePaletteTitle.textContent = t("themePalette");
  themeTextTitle.textContent = t("themeText");
  themeColorTitle.textContent = t("themeColor");
  themeBackgroundTitle.textContent = t("background");
  themeLineTitle.textContent = t("lines");
  interfaceFontTitle.textContent = t("interfaceFont");
  interfaceSizeTitle.textContent = t("interfaceSize");
  if (editorTitle) {
    editorTitle.textContent = t("editor");
  }
  if (editorFontCardTitle) {
    editorFontCardTitle.textContent = t("font");
  }
  if (editorColorCardTitle) {
    editorColorCardTitle.textContent = t("color");
  }
  if (editorConfigTitle) {
    editorConfigTitle.textContent = t("themeConfig");
  }
  glyphCompositionTitle.textContent = t("glyphComposition");
  tabSizeTitle.textContent = t("tabSize");
  editorFontTitle.textContent = t("editorFont");
  editorFontSizeTitle.textContent = t("editorFontSize");
  editorPaletteTitle.textContent = t("palette");
  editorBackgroundTitle.textContent = t("editorBackground");
  textColorTitle.textContent = t("textColor");
  textHighlightTitle.textContent = t("textHighlight");
  blockTitle.textContent = t("block");
  lineTitle.textContent = t("line");
  selectionTitle.textContent = t("selection");
  symbolColorsTitle.textContent = t("symbolHighlight");
  themeModeToggle?.setAttribute("aria-label", `${t("theme")} ${t("mode")}`);
  editorModeToggle?.setAttribute("aria-label", `${t("editor")} ${t("mode")}`);
  indentControl?.setAttribute("aria-label", t("tabSize"));

  workspaceCalloutTitle.textContent = t("usingBrowserStorage");
  workspaceCalloutBody.textContent = t("usingBrowserStorageBody");
  workspaceCalloutOpen.textContent = t("openWorkspace");

  appDialogTitle.textContent = t("dialog");
  appDialogClose.setAttribute("aria-label", t("closeDialog"));
  appDialogClose.setAttribute("title", t("closeDialog"));

  workspacePickerTitle.textContent = t("openWorkspaceTitle");
  workspacePickerCaption.textContent = t("chooseWorkspaceRoot");
  workspacePickerClose.setAttribute("aria-label", t("closeWorkspacePicker"));
  workspacePickerClose.setAttribute("title", t("closeWorkspacePicker"));
  workspacePickerUp.setAttribute("aria-label", t("goToParentFolder"));
  workspacePickerUp.setAttribute("title", t("goToParentFolder"));
  workspacePickerCurrent.setAttribute("aria-label", t("workspacePath"));
  importThemeConfigButton.setAttribute("aria-label", t("importConfig"));
  importThemeConfigButton.setAttribute("title", t("importConfig"));
  editThemeConfigButton.setAttribute("aria-label", t("editConfig"));
  editThemeConfigButton.setAttribute("title", t("editConfig"));
  importEditorConfigButton.setAttribute("aria-label", t("importConfig"));
  importEditorConfigButton.setAttribute("title", t("importConfig"));
  editEditorConfigButton.setAttribute("aria-label", t("editConfig"));
  editEditorConfigButton.setAttribute("title", t("editConfig"));

  workspacePickerTitle.textContent = workspacePickerTitleText || t("openWorkspaceTitle");
  workspacePickerCaption.textContent = workspacePickerDefaultCaptionText || t("chooseWorkspaceRoot");
  workspacePickerConfirm.textContent = workspacePickerConfirmText || t("useThisFolder");

  appDialogCancel.textContent = t("cancel");
  toggleGlyphs.setAttribute("aria-label", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
  toggleGlyphs.setAttribute("title", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
}

function getCaretLineIndex() {
  const beforeCaret = editorInput.value.slice(0, editorInput.selectionStart);
  return beforeCaret.split("\n").length - 1;
}

function normalizedSelectionRange() {
  return {
    start: Math.min(editorInput.selectionStart, editorInput.selectionEnd),
    end: Math.max(editorInput.selectionStart, editorInput.selectionEnd),
  };
}

function hasSelection() {
  const { start, end } = normalizedSelectionRange();
  return start !== end;
}

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function normalizeHexColor(value, fallback) {
  const match = value.trim().match(/^#?([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (!match) {
    return fallback;
  }

  let hex = match[1].toUpperCase();
  if (hex.length === 3) {
    hex = hex
      .split("")
      .map((char) => `${char}${char}`)
      .join("");
  }

  return `#${hex}`;
}

function findPresetByKeyOrLabel(options, value) {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim();
  if (!normalized) {
    return null;
  }

  return (
    options.find((option) => option.key === normalized) ??
    options.find((option) => option.label.toLowerCase() === normalized.toLowerCase()) ??
    null
  );
}

function stripJsonComments(source) {
  let result = "";
  let inString = false;
  let stringQuote = "";
  let escaping = false;

  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];

    if (inString) {
      result += current;
      if (escaping) {
        escaping = false;
      } else if (current === "\\") {
        escaping = true;
      } else if (current === stringQuote) {
        inString = false;
        stringQuote = "";
      }
      continue;
    }

    if (current === '"' || current === "'") {
      inString = true;
      stringQuote = current;
      result += current;
      continue;
    }

    if (current === "/" && next === "/") {
      while (index < source.length && source[index] !== "\n") {
        index += 1;
      }
      if (index < source.length) {
        result += source[index];
      }
      continue;
    }

    if (current === "/" && next === "*") {
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) {
        index += 1;
      }
      index += 1;
      continue;
    }

    result += current;
  }

  return result;
}

function stripTrailingCommas(source) {
  let result = "";
  let inString = false;
  let stringQuote = "";
  let escaping = false;

  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];

    if (inString) {
      result += current;
      if (escaping) {
        escaping = false;
      } else if (current === "\\") {
        escaping = true;
      } else if (current === stringQuote) {
        inString = false;
        stringQuote = "";
      }
      continue;
    }

    if (current === '"' || current === "'") {
      inString = true;
      stringQuote = current;
      result += current;
      continue;
    }

    if (current === ",") {
      let cursor = index + 1;
      while (cursor < source.length && /\s/.test(source[cursor])) {
        cursor += 1;
      }
      if (source[cursor] === "}" || source[cursor] === "]") {
        continue;
      }
    }

    result += current;
  }

  return result;
}

function parseJsonc(source) {
  const withoutComments = stripJsonComments(source);
  const withoutTrailingCommas = stripTrailingCommas(withoutComments);
  return JSON.parse(withoutTrailingCommas);
}

function glyphSpecFromConfigKey(key) {
  if (typeof key !== "string") {
    return null;
  }

  const normalized = key.trim();
  if (!normalized) {
    return null;
  }

  return (
    glyphColorSpecs.find((spec) => spec.key === normalized) ??
    glyphColorSpecs.find((spec) => spec.token === normalized) ??
    null
  );
}

function normalizeEditorFontSizeFromConfig(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value);
    return editorFontSizePresets.find((preset) => preset.size === rounded)?.key ?? null;
  }

  if (typeof value === "string") {
    const normalized = value.trim();
    return (
      findPresetByKeyOrLabel(editorFontSizePresets, normalized)?.key ??
      legacyEditorFontSizeKeyMap[normalized] ??
      null
    );
  }

  return null;
}

function normalizeInterfaceSizeFromConfig(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    const rounded = Math.round(value);
    return interfaceSizeOptionsList.find((option) => option.size === rounded)?.key ?? null;
  }

  if (typeof value === "string") {
    const normalized = value.trim();
    return (
      findPresetByKeyOrLabel(interfaceSizeOptionsList, normalized)?.key ??
      legacyInterfaceSizeKeyMap[normalized] ??
      null
    );
  }

  return null;
}

function normalizeLegacyPresetValue(value, legacyMap) {
  if (typeof value !== "string") {
    return value;
  }

  const normalized = value.trim();
  return legacyMap[normalized] ?? normalized;
}

function parseCustomPaletteConfig(rawText) {
  let parsed;
  try {
    parsed = parseJsonc(rawText);
  } catch (error) {
    throw new Error(`${t("configParseFailed")}: ${error.message}`);
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`${t("configParseFailed")}: root must be an object`);
  }

  const workbench = parsed["workbench.colorCustomizations"];
  const editorColors = parsed["editor.tokenColorCustomizations"];
  const editorConfig = parsed.editor;
  const styioView = parsed.styioView;

  const config = {
    name: typeof parsed.name === "string" ? parsed.name.trim() : "",
    styleKey:
      findPresetByKeyOrLabel(uiStyleOptionsList, normalizeLegacyPresetValue(styioView?.style, legacyUiStyleKeyMap))
        ?.key ?? null,
    languageKey: findPresetByKeyOrLabel(languageOptionsList, styioView?.language)?.key ?? null,
    themeMode: ["dark", "light"].includes(styioView?.themeMode) ? styioView.themeMode : null,
    editorMode: ["dark", "light"].includes(styioView?.editorMode) ? styioView.editorMode : null,
    themePaletteKey:
      findPresetByKeyOrLabel(themePalettePresets, workbench?.["styio.themePalette"])?.key ?? null,
    themeColorKey:
      findPresetByKeyOrLabel(
        themeColorPresets,
        normalizeLegacyPresetValue(workbench?.["styio.themeColor"], legacyThemeColorKeyMap),
      )?.key ?? null,
    themeTextKey:
      findPresetByKeyOrLabel(themeTextPresets, workbench?.["styio.themeText"])?.key ?? null,
    themeBackgroundKey:
      findPresetByKeyOrLabel(themeBackgroundPresets, workbench?.["styio.background"])?.key ?? null,
    themeLineKey:
      findPresetByKeyOrLabel(themeLinePresets, workbench?.["styio.themeLines"])?.key ?? null,
    interfaceFontKey:
      findPresetByKeyOrLabel(
        interfaceFontOptionsList,
        normalizeLegacyPresetValue(workbench?.["styio.interfaceFont"], legacyInterfaceFontKeyMap),
      )?.key ?? null,
    interfaceSizeKey: normalizeInterfaceSizeFromConfig(workbench?.["styio.interfaceSize"]),
    editorFontKey:
      findPresetByKeyOrLabel(
        editorFontOptionsList,
        normalizeLegacyPresetValue(editorConfig?.fontFamily, legacyEditorFontKeyMap),
      )?.key ?? null,
    editorFontSizeKey: normalizeEditorFontSizeFromConfig(editorConfig?.fontSize),
    tabSize: [2, 4].includes(editorConfig?.tabSize) ? editorConfig.tabSize : null,
    glyphComposition:
      typeof styioView?.glyphComposition === "boolean" ? styioView.glyphComposition : null,
    editorPaletteKey:
      findPresetByKeyOrLabel(
        glyphPaletteOptions,
        normalizeLegacyPresetValue(editorColors?.["styio.palette"], legacyDefaultGlyphPaletteKeyMap),
      )?.key ?? null,
    editorBackgroundKey:
      findPresetByKeyOrLabel(editorBackgroundPresets, editorColors?.["styio.editorBackground"])?.key ??
      null,
    textColorKey:
      findPresetByKeyOrLabel(editorTextColorPresets, editorColors?.["styio.textColor"])?.key ?? null,
    textHighlightKey:
      findPresetByKeyOrLabel(
        editorTextHighlightPresets,
        normalizeLegacyPresetValue(editorColors?.["styio.textHighlight"], legacyEditorTextHighlightKeyMap),
      )?.key ?? null,
    blockSurfaceKey:
      findPresetByKeyOrLabel(blockSurfacePresets, editorColors?.["styio.block"])?.key ?? null,
    lineHighlightKey:
      findPresetByKeyOrLabel(lineHighlightPresets, editorColors?.["styio.line"])?.key ?? null,
    selectionHighlightKey:
      findPresetByKeyOrLabel(selectionHighlightPresets, editorColors?.["styio.selection"])?.key ?? null,
    symbolColors: {},
    visualTokens: normalizeVisualTokenOverrides(styioView?.visualTokens),
    replaceVisualTokens: Object.prototype.hasOwnProperty.call(styioView ?? {}, "visualTokens"),
  };

  const symbolColors = editorColors?.["styio.symbolColors"];
  if (symbolColors && typeof symbolColors === "object" && !Array.isArray(symbolColors)) {
    Object.entries(symbolColors).forEach(([key, value]) => {
      const spec = glyphSpecFromConfigKey(key);
      if (!spec || typeof value !== "string") {
        return;
      }
      config.symbolColors[spec.key] = normalizeHexColor(value, glyphColors[spec.key] ?? defaultGlyphColor);
    });
  }

  return config;
}

function buildCustomPaletteConfigObject() {
  const symbolColors = {};
  glyphColorSpecs.forEach((spec) => {
    symbolColors[spec.key] = glyphColors[spec.key];
  });

  const currentInterfaceSize = currentInterfaceSizeOption();
  const currentEditorFontSize = currentEditorFontSizePreset();
  const editorFontSizeValue = Number.parseInt(
    currentEditorFontSize.vars["--editor-font-size"].replace("px", ""),
    10,
  );

  return {
    $schema: customPaletteConfigSchema,
    name: "Custom Palette",
    "workbench.colorCustomizations": {
      "styio.themePalette": currentThemePaletteSelectionKey(),
      "styio.themeColor": activeThemeColorKey,
      "styio.themeText": activeThemeTextKey,
      "styio.background": activeThemeBackgroundKey,
      "styio.themeLines": activeThemeLineKey,
      "styio.interfaceFont": activeInterfaceFontKey,
      "styio.interfaceSize": currentInterfaceSize.size,
    },
    editor: {
      tabSize: indentSize,
      fontFamily: activeEditorFontKey,
      fontSize: Number.isFinite(editorFontSizeValue) ? editorFontSizeValue : currentEditorFontSize.size,
    },
    styioView: {
      style: activeUiStyleKey,
      language: activeLanguageKey,
      glyphComposition: glyphsOn,
      themeMode,
      editorMode,
    },
    "editor.tokenColorCustomizations": {
      "styio.palette": currentEditorPaletteSelectionKey(),
      "styio.editorBackground": activeEditorBackgroundKey,
      "styio.textColor": activeEditorTextColorKey,
      "styio.textHighlight": activeEditorTextHighlightKey,
      "styio.block": activeBlockSurfaceKey,
      "styio.line": activeLineHighlightKey,
      "styio.selection": activeSelectionHighlightKey,
      "styio.symbolColors": symbolColors,
    },
  };
}

function buildCustomPaletteConfigText() {
  const config = buildCustomPaletteConfigObject();
  if (hasVisualTokenOverrides(visualTokenOverrides)) {
    config.styioView.visualTokens = buildVisualTokenConfigObject(visualTokenOverrides);
  }
  return JSON.stringify(config, null, 2);
}

function persistThemeSettings() {
  try {
    window.localStorage.setItem(
      themeSettingsStorageKey,
      JSON.stringify({
        themeMode,
        themePaletteKey: currentThemePaletteSelectionKey(),
        themeColorKey: activeThemeColorKey,
        themeTextKey: activeThemeTextKey,
        themeBackgroundKey: activeThemeBackgroundKey,
        themeLineKey: activeThemeLineKey,
        interfaceFontKey: activeInterfaceFontKey,
        interfaceSizeKey: activeInterfaceSizeKey,
      }),
    );
  } catch (error) {
    console.warn("failed to persist theme settings", error);
  }
  persistCustomPaletteConfigState();
}

function loadThemeSettings() {
  try {
    const raw = window.localStorage.getItem(themeSettingsStorageKey);
    if (!raw) {
      return;
    }

    const parsed = JSON.parse(raw);
    if (parsed?.themeMode === "dark" || parsed?.themeMode === "light") {
      themeMode = parsed.themeMode;
    }
    if (themePalettePresets.some((preset) => preset.key === parsed?.themePaletteKey)) {
      activeThemePaletteKey = parsed.themePaletteKey;
      themeMode = themePalettePresets.find((preset) => preset.key === parsed.themePaletteKey)?.mode ?? themeMode;
    } else {
      activeThemePaletteKey = defaultThemePaletteForMode(themeMode).key;
    }
    const migratedThemeColorKey = legacyThemeColorKeyMap[parsed?.themeColorKey] ?? parsed?.themeColorKey;
    if (themeColorPresets.some((preset) => preset.key === migratedThemeColorKey)) {
      activeThemeColorKey = migratedThemeColorKey;
    }
    if (themeTextPresets.some((preset) => preset.key === parsed?.themeTextKey)) {
      activeThemeTextKey = parsed.themeTextKey;
    }
    if (themeBackgroundPresets.some((preset) => preset.key === parsed?.themeBackgroundKey)) {
      activeThemeBackgroundKey = parsed.themeBackgroundKey;
    }
    if (themeLinePresets.some((preset) => preset.key === parsed?.themeLineKey)) {
      activeThemeLineKey = parsed.themeLineKey;
    }
    const migratedInterfaceFontKey =
      legacyInterfaceFontKeyMap[parsed?.interfaceFontKey] ?? parsed?.interfaceFontKey;
    if (interfaceFontOptionsList.some((option) => option.key === migratedInterfaceFontKey)) {
      activeInterfaceFontKey = migratedInterfaceFontKey;
    }
    const migratedInterfaceSizeKey = legacyInterfaceSizeKeyMap[parsed?.interfaceSizeKey] ?? parsed?.interfaceSizeKey;
    if (interfaceSizeOptionsList.some((option) => option.key === migratedInterfaceSizeKey)) {
      activeInterfaceSizeKey = migratedInterfaceSizeKey;
    }
    coerceThemeSelectionsForMode();
  } catch (error) {
    console.warn("failed to restore theme settings", error);
  }
}

function persistEditorPreferences() {
  try {
    window.localStorage.setItem(
      editorSettingsStorageKey,
      JSON.stringify({
        editorMode,
        glyphsOn,
        indentSize,
        editorFontKey: activeEditorFontKey,
        editorFontSizeKey: activeEditorFontSizeKey,
        paletteKey: currentEditorPaletteSelectionKey(),
        editorBackgroundKey: activeEditorBackgroundKey,
        editorTextColorKey: activeEditorTextColorKey,
        editorTextHighlightKey: activeEditorTextHighlightKey,
        blockSurfaceKey: activeBlockSurfaceKey,
        lineHighlightKey: activeLineHighlightKey,
        selectionHighlightKey: activeSelectionHighlightKey,
      }),
    );
  } catch (error) {
    console.warn("failed to persist editor settings", error);
  }
  persistCustomPaletteConfigState();
}

function persistCustomPaletteConfigState() {
  try {
    window.localStorage.setItem(customPaletteConfigStorageKey, buildCustomPaletteConfigText());
  } catch (error) {
    console.warn("failed to persist custom palette config", error);
  }
}

function applyCustomPaletteConfig(config) {
  if (config.styleKey) {
    activeUiStyleKey = config.styleKey;
  }
  if (config.languageKey) {
    activeLanguageKey = config.languageKey;
  }
  if (config.themeMode === "dark" || config.themeMode === "light") {
    themeMode = config.themeMode;
  }
  if (config.editorMode === "dark" || config.editorMode === "light") {
    editorMode = config.editorMode;
  }
  if (config.themePaletteKey) {
    applyThemePaletteSelection(config.themePaletteKey);
  }
  if (config.themeColorKey) {
    activeThemeColorKey = config.themeColorKey;
  }
  if (config.themeTextKey) {
    activeThemeTextKey = config.themeTextKey;
  }
  if (config.themeBackgroundKey) {
    activeThemeBackgroundKey = config.themeBackgroundKey;
  }
  if (config.themeLineKey) {
    activeThemeLineKey = config.themeLineKey;
  }
  if (config.interfaceFontKey) {
    activeInterfaceFontKey = config.interfaceFontKey;
  }
  if (config.interfaceSizeKey) {
    activeInterfaceSizeKey = config.interfaceSizeKey;
  }
  if (config.editorFontKey) {
    activeEditorFontKey = config.editorFontKey;
  }
  if (config.editorFontSizeKey) {
    activeEditorFontSizeKey = config.editorFontSizeKey;
  }
  if (config.tabSize) {
    indentSize = config.tabSize;
  }
  if (typeof config.glyphComposition === "boolean") {
    glyphsOn = config.glyphComposition;
  }
  if (config.editorPaletteKey) {
    applyEditorPaletteSelection(config.editorPaletteKey);
  }
  if (config.editorBackgroundKey) {
    activeEditorBackgroundKey = config.editorBackgroundKey;
  }
  if (config.textColorKey) {
    activeEditorTextColorKey = config.textColorKey;
  }
  if (config.textHighlightKey) {
    activeEditorTextHighlightKey = config.textHighlightKey;
  }
  if (config.blockSurfaceKey) {
    activeBlockSurfaceKey = config.blockSurfaceKey;
  }
  if (config.lineHighlightKey) {
    activeLineHighlightKey = config.lineHighlightKey;
  }
  if (config.selectionHighlightKey) {
    activeSelectionHighlightKey = config.selectionHighlightKey;
  }
  Object.entries(config.symbolColors).forEach(([key, value]) => {
    glyphColors[key] = value;
  });
  if (config.replaceVisualTokens) {
    visualTokenOverrides = { ...config.visualTokens };
  } else if (hasVisualTokenOverrides(config.visualTokens)) {
    visualTokenOverrides = {
      ...visualTokenOverrides,
      ...config.visualTokens,
    };
  }
  coerceThemeSelectionsForMode();
  coerceEditorSelectionsForMode();
  applyLanguageUi();
  applyUiStyleStrategy();
}

function loadCustomPaletteConfigState() {
  try {
    const raw = window.localStorage.getItem(customPaletteConfigStorageKey);
    if (!raw) {
      return;
    }

    const parsed = parseCustomPaletteConfig(raw);
    applyCustomPaletteConfig(parsed);
  } catch (error) {
    console.warn("failed to restore custom palette config", error);
  }
}

function loadEditorPreferences() {
  try {
    const raw = window.localStorage.getItem(editorSettingsStorageKey);
    if (!raw) {
      return;
    }

    const parsed = JSON.parse(raw);
    if (parsed?.editorMode === "dark" || parsed?.editorMode === "light") {
      editorMode = parsed.editorMode;
    }
    if (typeof parsed?.glyphsOn === "boolean") {
      glyphsOn = parsed.glyphsOn;
    }
    if ([2, 4].includes(parsed?.indentSize)) {
      indentSize = parsed.indentSize;
    }
    const migratedEditorFontKey = legacyEditorFontKeyMap[parsed?.editorFontKey] ?? parsed?.editorFontKey;
    if (editorFontOptionsList.some((option) => option.key === migratedEditorFontKey)) {
      activeEditorFontKey = migratedEditorFontKey;
    }
    const migratedEditorFontSizeKey =
      legacyEditorFontSizeKeyMap[parsed?.editorFontSizeKey] ?? parsed?.editorFontSizeKey;
    if (editorFontSizePresets.some((preset) => preset.key === migratedEditorFontSizeKey)) {
      activeEditorFontSizeKey = migratedEditorFontSizeKey;
    }
    if (editorBackgroundPresets.some((preset) => preset.key === parsed?.editorBackgroundKey)) {
      activeEditorBackgroundKey = parsed.editorBackgroundKey;
    }
    if (editorTextColorPresets.some((preset) => preset.key === parsed?.editorTextColorKey)) {
      activeEditorTextColorKey = parsed.editorTextColorKey;
    }
    const migratedEditorTextHighlightKey =
      legacyEditorTextHighlightKeyMap[parsed?.editorTextHighlightKey] ?? parsed?.editorTextHighlightKey;
    if (editorTextHighlightPresets.some((preset) => preset.key === migratedEditorTextHighlightKey)) {
      activeEditorTextHighlightKey = migratedEditorTextHighlightKey;
    }
    const migratedPaletteKey = legacyGlyphPaletteKeyMap[parsed?.paletteKey] ?? parsed?.paletteKey;
    if (glyphPaletteOptions.some((palette) => palette.key === migratedPaletteKey)) {
      activePaletteKey = migratedPaletteKey;
      editorMode = editorPaletteMeta[migratedPaletteKey]?.mode ?? editorMode;
    } else {
      activePaletteKey = defaultEditorPaletteForMode(editorMode).key;
    }
    if (blockSurfacePresets.some((preset) => preset.key === parsed?.blockSurfaceKey)) {
      activeBlockSurfaceKey = parsed.blockSurfaceKey;
    }
    if (lineHighlightPresets.some((preset) => preset.key === parsed?.lineHighlightKey)) {
      activeLineHighlightKey = parsed.lineHighlightKey;
    }
    if (selectionHighlightPresets.some((preset) => preset.key === parsed?.selectionHighlightKey)) {
      activeSelectionHighlightKey = parsed.selectionHighlightKey;
    }
    coerceEditorSelectionsForMode();
  } catch (error) {
    console.warn("failed to restore editor settings", error);
  }
}

function currentThemeTextOptions() {
  return themeTextPresets.filter((preset) => preset.mode === themeMode);
}

function currentThemeBackgroundOptions() {
  return themeBackgroundPresets.filter((preset) => preset.mode === themeMode);
}

function currentThemeLineOptions() {
  return themeLinePresets.filter((preset) => preset.mode === themeMode);
}

function currentEditorBackgroundOptions() {
  return editorBackgroundPresets.filter((preset) => preset.mode === editorMode);
}

function currentEditorTextColorOptions() {
  return editorTextColorPresets.filter((preset) => preset.mode === editorMode);
}

function coerceThemeSelectionsForMode() {
  const fallbackPalette = currentThemePalette();
  if (!currentThemeTextOptions().some((preset) => preset.key === activeThemeTextKey)) {
    activeThemeTextKey = fallbackPalette.themeTextKey;
  }
  if (!currentThemeBackgroundOptions().some((preset) => preset.key === activeThemeBackgroundKey)) {
    activeThemeBackgroundKey = fallbackPalette.themeBackgroundKey;
  }
  if (!currentThemeLineOptions().some((preset) => preset.key === activeThemeLineKey)) {
    activeThemeLineKey = fallbackPalette.themeLineKey;
  }
}

function coerceEditorSelectionsForMode() {
  const fallbackPalette = currentPalette();
  const paletteMeta = editorPaletteMeta[fallbackPalette.key] ?? {};
  if (!currentEditorBackgroundOptions().some((preset) => preset.key === activeEditorBackgroundKey)) {
    activeEditorBackgroundKey = paletteMeta.backgroundKey ?? currentEditorBackgroundOptions()[0]?.key ?? editorBackgroundPresets[0].key;
  }
  if (!currentEditorTextColorOptions().some((preset) => preset.key === activeEditorTextColorKey)) {
    activeEditorTextColorKey = paletteMeta.textColorKey ?? currentEditorTextColorOptions()[0]?.key ?? editorTextColorPresets[0].key;
  }
}

function currentThemeColorPreset() {
  return themeColorPresets.find((preset) => preset.key === activeThemeColorKey) ?? themeColorPresets[0];
}

function currentThemeBackgroundPreset() {
  return (
    currentThemeBackgroundOptions().find((preset) => preset.key === activeThemeBackgroundKey) ??
    currentThemeBackgroundOptions()[0] ??
    themeBackgroundPresets[0]
  );
}

function currentInterfaceFontOption() {
  return (
    interfaceFontOptionsList.find((option) => option.key === activeInterfaceFontKey) ??
    interfaceFontOptionsList[0]
  );
}

function currentInterfaceSizeOption() {
  return (
    interfaceSizeOptionsList.find((option) => option.key === activeInterfaceSizeKey) ??
    interfaceSizeOptionsList[0]
  );
}

function currentEditorFontOption() {
  return (
    editorFontOptionsList.find((option) => option.key === activeEditorFontKey) ??
    editorFontOptionsList[0]
  );
}

function currentEditorFontSizePreset() {
  return (
    editorFontSizePresets.find((preset) => preset.key === activeEditorFontSizeKey) ??
    editorFontSizePresets[0]
  );
}

function stepInterfaceSize(direction) {
  const options = interfaceSizeOptionsList;
  const currentIndex = Math.max(
    0,
    options.findIndex((option) => option.key === activeInterfaceSizeKey),
  );
  const nextIndex = Math.min(options.length - 1, Math.max(0, currentIndex + direction));
  if (nextIndex === currentIndex) {
    return;
  }

  dispatchSurfaceAction(SURFACE_ACTIONS.INTERFACE_SIZE, () => {
    activeInterfaceSizeKey = options[nextIndex].key;
  });
}

function stepEditorFontSize(direction) {
  const presets = editorFontSizePresets;
  const currentIndex = Math.max(
    0,
    presets.findIndex((preset) => preset.key === activeEditorFontSizeKey),
  );
  const nextIndex = Math.min(presets.length - 1, Math.max(0, currentIndex + direction));
  if (nextIndex === currentIndex) {
    return;
  }

  dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_FONT_SIZE, () => {
    activeEditorFontSizeKey = presets[nextIndex].key;
  });
}

function currentEditorBackgroundPreset() {
  return (
    currentEditorBackgroundOptions().find((preset) => preset.key === activeEditorBackgroundKey) ??
    currentEditorBackgroundOptions()[0] ??
    editorBackgroundPresets[0]
  );
}

function currentEditorTextColorPreset() {
  return (
    currentEditorTextColorOptions().find((preset) => preset.key === activeEditorTextColorKey) ??
    currentEditorTextColorOptions()[0] ??
    editorTextColorPresets[0]
  );
}

function currentEditorTextHighlightPreset() {
  return (
    editorTextHighlightPresets.find((preset) => preset.key === activeEditorTextHighlightKey) ??
    editorTextHighlightPresets[0]
  );
}

function applyThemeColorTheme() {
  Object.entries(currentThemeColorPreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyThemeBackgroundTheme() {
  Object.entries(currentThemeBackgroundPreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyInterfaceFontTheme() {
  document.documentElement.style.setProperty("--ui-font-family", currentInterfaceFontOption().value);
}

function applyInterfaceSizeTheme() {
  Object.entries(currentInterfaceSizeOption().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyEditorFontTheme() {
  document.documentElement.style.setProperty("--editor-font-family", currentEditorFontOption().value);
}

function applyEditorFontSizeTheme() {
  Object.entries(currentEditorFontSizePreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyEditorBackgroundTheme() {
  Object.entries(currentEditorBackgroundPreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyEditorTextColorTheme() {
  Object.entries(currentEditorTextColorPreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyEditorTextHighlightTheme() {
  const preset = currentEditorTextHighlightPreset();
  document.documentElement.style.setProperty("--editor-text-highlight", preset.color);
  document.documentElement.style.setProperty("--editor-caret", preset.color);
  document.documentElement.style.setProperty("--editor-caret-shadow", preset.caretShadow);
}

function currentThemeTextPreset() {
  return currentThemeTextOptions().find((preset) => preset.key === activeThemeTextKey) ?? currentThemeTextOptions()[0] ?? themeTextPresets[0];
}

function currentThemeLinePreset() {
  return currentThemeLineOptions().find((preset) => preset.key === activeThemeLineKey) ?? currentThemeLineOptions()[0] ?? themeLinePresets[0];
}

function currentThemeModeOptions() {
  return themePalettePresets.filter((palette) => palette.mode === themeMode);
}

function defaultThemePaletteForMode(mode) {
  return themePalettePresets.find((palette) => palette.mode === mode) ?? themePalettePresets[0];
}

function matchedThemePalette() {
  return (
    themePalettePresets.find(
      (palette) =>
        palette.mode === themeMode &&
        palette.themeColorKey === activeThemeColorKey &&
        palette.themeTextKey === activeThemeTextKey &&
        palette.themeBackgroundKey === activeThemeBackgroundKey &&
        palette.themeLineKey === activeThemeLineKey,
    ) ?? null
  );
}

function currentThemePaletteSelectionKey() {
  return matchedThemePalette()?.key ?? "customized";
}

function currentThemePaletteLabel() {
  return matchedThemePalette()?.label ?? t("customized");
}

function currentThemePalette() {
  const byKey = themePalettePresets.find((palette) => palette.key === activeThemePaletteKey);
  if (byKey && byKey.mode === themeMode) {
    return byKey;
  }
  return currentThemeModeOptions()[0] ?? themePalettePresets[0];
}

function applyThemeTextTheme() {
  Object.entries(currentThemeTextPreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyThemeLineTheme() {
  Object.entries(currentThemeLinePreset().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyWorkbenchThemeState() {
  document.documentElement.style.colorScheme = themeMode;
  document.body.dataset.themeMode = themeMode;
  document.body.dataset.editorMode = editorMode;
  applyThemeBackgroundTheme();
  applyThemeTextTheme();
  applyThemeColorTheme();
  applyThemeLineTheme();
  applyInterfaceFontTheme();
  applyInterfaceSizeTheme();
}

function applyThemePaletteSelection(paletteKey) {
  const palette = themePalettePresets.find((entry) => entry.key === paletteKey);
  if (!palette) {
    return;
  }

  activeThemePaletteKey = palette.key;
  themeMode = palette.mode;
  activeThemeColorKey = palette.themeColorKey;
  activeThemeTextKey = palette.themeTextKey;
  activeThemeBackgroundKey = palette.themeBackgroundKey;
  activeThemeLineKey = palette.themeLineKey;
}

function syncThemeUi() {
  coerceThemeSelectionsForMode();
  syncDropdownControl({
    nodeId: "themePalette",
    button: themePaletteButton,
    menu: themePaletteOptionsMenu,
    label: currentThemePaletteLabel(),
    open: themePaletteMenuOpen,
    options: currentThemeModeOptions().map((palette) => ({ key: palette.key, label: palette.label })),
    activeKey: currentThemePaletteSelectionKey(),
  });
  syncDropdownControl({
    nodeId: "themeText",
    button: themeTextButton,
    menu: themeTextOptions,
    label: currentThemeTextPreset().label,
    open: themeTextMenuOpen,
    options: currentThemeTextOptions().map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeThemeTextKey,
  });
  syncDropdownControl({
    nodeId: "themeColor",
    button: themeColorButton,
    menu: themeColorOptions,
    label: currentThemeColorPreset().label,
    open: themeColorMenuOpen,
    options: themeColorPresets.map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeThemeColorKey,
  });
  syncDropdownControl({
    nodeId: "themeBackground",
    button: themeBackgroundButton,
    menu: themeBackgroundOptions,
    label: currentThemeBackgroundPreset().label,
    open: themeBackgroundMenuOpen,
    options: currentThemeBackgroundOptions().map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeThemeBackgroundKey,
  });
  syncDropdownControl({
    nodeId: "themeLines",
    button: themeLineButton,
    menu: themeLineOptions,
    label: currentThemeLinePreset().label,
    open: themeLineMenuOpen,
    options: currentThemeLineOptions().map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeThemeLineKey,
  });
  syncDropdownControl({
    nodeId: "interfaceFont",
    button: interfaceFontButton,
    menu: interfaceFontOptions,
    label: currentInterfaceFontOption().label,
    open: interfaceFontMenuOpen,
    options: interfaceFontOptionsList.map((option) => ({ key: option.key, label: option.label })),
    activeKey: activeInterfaceFontKey,
  });

  const currentInterfaceSize = currentInterfaceSizeOption();
  interfaceSizeValue.textContent = String(currentInterfaceSize.size);
  interfaceSizeDecrease.disabled = currentInterfaceSize.size <= interfaceSizeOptionsList[0].size;
  interfaceSizeIncrease.disabled =
    currentInterfaceSize.size >= interfaceSizeOptionsList[interfaceSizeOptionsList.length - 1].size;

  themeModeDark?.classList.toggle("is-active", themeMode === "dark");
  themeModeLight?.classList.toggle("is-active", themeMode === "light");
  themeModeDark?.setAttribute("aria-pressed", String(themeMode === "dark"));
  themeModeLight?.setAttribute("aria-pressed", String(themeMode === "light"));
  themeModeToggle?.setAttribute("data-mode", themeMode);
  themeModeDark?.toggleAttribute("disabled", false);
  themeModeLight?.toggleAttribute("disabled", false);
  themeModeToggle?.classList.remove("is-disabled");
}

function renderThemeControls() {
  syncThemeUi();
}

function syncEditorPreferencesUi() {
  coerceEditorSelectionsForMode();

  const editorModeLocked = editorModeLinkedToTheme;
  editorModeDark?.classList.toggle("is-active", editorMode === "dark");
  editorModeLight?.classList.toggle("is-active", editorMode === "light");
  editorModeDark?.setAttribute("aria-pressed", String(editorMode === "dark"));
  editorModeLight?.setAttribute("aria-pressed", String(editorMode === "light"));
  editorModeToggle?.setAttribute("data-mode", editorMode);
  editorModeDark?.toggleAttribute("disabled", editorModeLocked);
  editorModeLight?.toggleAttribute("disabled", editorModeLocked);
  editorModeToggle?.classList.toggle("is-disabled", editorModeLocked);

  syncDropdownControl({
    nodeId: "editorFont",
    button: editorFontButton,
    menu: editorFontOptions,
    label: currentEditorFontOption().label,
    open: editorFontMenuOpen,
    options: editorFontOptionsList.map((option) => ({ key: option.key, label: option.label })),
    activeKey: activeEditorFontKey,
  });

  const currentEditorFontSize = currentEditorFontSizePreset();
  editorFontSizeValue.textContent = String(currentEditorFontSize.size);
  editorFontSizeDecrease.disabled = currentEditorFontSize.size <= editorFontSizePresets[0].size;
  editorFontSizeIncrease.disabled =
    currentEditorFontSize.size >= editorFontSizePresets[editorFontSizePresets.length - 1].size;

  syncDropdownControl({
    nodeId: "editorBackground",
    button: editorBackgroundButton,
    menu: editorBackgroundOptions,
    label: currentEditorBackgroundPreset().label,
    open: editorBackgroundMenuOpen,
    options: currentEditorBackgroundOptions().map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeEditorBackgroundKey,
  });
  syncDropdownControl({
    nodeId: "editorTextColor",
    button: textColorButton,
    menu: textColorOptions,
    label: currentEditorTextColorPreset().label,
    open: textColorMenuOpen,
    options: currentEditorTextColorOptions().map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeEditorTextColorKey,
  });
  syncDropdownControl({
    nodeId: "editorTextHighlight",
    button: textHighlightButton,
    menu: textHighlightOptions,
    label: currentEditorTextHighlightPreset().label,
    open: textHighlightMenuOpen,
    options: editorTextHighlightPresets.map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeEditorTextHighlightKey,
  });
}

function syncLinkedSurfaceModeCardUi() {
  linkedSurfaceModeTitle?.replaceChildren(document.createTextNode(t("mode")));
  linkedSurfaceThemeTab?.replaceChildren(document.createTextNode(t("theme")));
  linkedSurfaceEditorTab?.replaceChildren(document.createTextNode(t("editor")));

  const isThemeTab = linkedSurfaceActiveTab === SURFACE_KEYS.THEME;
  const currentMode = isThemeTab ? themeMode : editorMode;
  const editorModeLocked = !isThemeTab && editorModeLinkedToTheme;

  linkedSurfaceThemeTab?.classList.toggle("is-active", isThemeTab);
  linkedSurfaceEditorTab?.classList.toggle("is-active", !isThemeTab);
  linkedSurfaceThemeTab?.setAttribute("aria-selected", String(isThemeTab));
  linkedSurfaceEditorTab?.setAttribute("aria-selected", String(!isThemeTab));
  linkedSurfaceThemePanel?.classList.toggle("is-active", isThemeTab);
  linkedSurfaceEditorPanel?.classList.toggle("is-active", !isThemeTab);
  linkedSurfaceThemePanel?.toggleAttribute("hidden", !isThemeTab);
  linkedSurfaceEditorPanel?.toggleAttribute("hidden", isThemeTab);

  linkedSurfaceModeToggle?.setAttribute("data-mode", currentMode);
  linkedSurfaceModeToggle?.classList.toggle("is-disabled", editorModeLocked);

  linkedSurfaceModeDark?.classList.toggle("is-active", currentMode === "dark");
  linkedSurfaceModeLight?.classList.toggle("is-active", currentMode === "light");
  linkedSurfaceModeDark?.setAttribute("aria-pressed", String(currentMode === "dark"));
  linkedSurfaceModeLight?.setAttribute("aria-pressed", String(currentMode === "light"));
  linkedSurfaceModeDark?.toggleAttribute("disabled", editorModeLocked);
  linkedSurfaceModeLight?.toggleAttribute("disabled", editorModeLocked);

  if (linkedEditorModeLinkButton) {
    linkedEditorModeLinkButton.hidden = isThemeTab;
    linkedEditorModeLinkButton.classList.toggle("is-linked", editorModeLinkedToTheme);
    linkedEditorModeLinkButton.setAttribute("aria-pressed", String(editorModeLinkedToTheme));
    const linkLabel = editorModeLinkedToTheme ? t("unlinkEditorMode") : t("linkEditorMode");
    linkedEditorModeLinkButton.setAttribute("aria-label", linkLabel);
    linkedEditorModeLinkButton.setAttribute("title", linkLabel);
  }
}

function renderEditorPreferenceControls() {
  syncEditorPreferencesUi();
}

const settingsMenuAliases = Object.freeze({
  palette: "editorPalette",
  themeLine: "themeLines",
  textColor: "editorTextColor",
  textHighlight: "editorTextHighlight",
  block: "editorBlockStyle",
  line: "editorLineStyle",
  selection: "editorSelectionStyle",
});

const settingsMenuControllers = Object.freeze({
  language: {
    get: () => languageMenuOpen,
    set: (nextValue) => {
      languageMenuOpen = nextValue;
    },
  },
  style: {
    get: () => styleMenuOpen,
    set: (nextValue) => {
      styleMenuOpen = nextValue;
    },
  },
  autoSave: {
    get: () => autoSaveMenuOpen,
    set: (nextValue) => {
      autoSaveMenuOpen = nextValue;
    },
  },
  themePalette: {
    get: () => themePaletteMenuOpen,
    set: (nextValue) => {
      themePaletteMenuOpen = nextValue;
    },
  },
  themeText: {
    get: () => themeTextMenuOpen,
    set: (nextValue) => {
      themeTextMenuOpen = nextValue;
    },
  },
  themeColor: {
    get: () => themeColorMenuOpen,
    set: (nextValue) => {
      themeColorMenuOpen = nextValue;
    },
  },
  themeBackground: {
    get: () => themeBackgroundMenuOpen,
    set: (nextValue) => {
      themeBackgroundMenuOpen = nextValue;
    },
  },
  themeLines: {
    get: () => themeLineMenuOpen,
    set: (nextValue) => {
      themeLineMenuOpen = nextValue;
    },
  },
  interfaceFont: {
    get: () => interfaceFontMenuOpen,
    set: (nextValue) => {
      interfaceFontMenuOpen = nextValue;
    },
  },
  editorFont: {
    get: () => editorFontMenuOpen,
    set: (nextValue) => {
      editorFontMenuOpen = nextValue;
    },
  },
  editorPalette: {
    get: () => paletteMenuOpen,
    set: (nextValue) => {
      paletteMenuOpen = nextValue;
    },
  },
  editorBackground: {
    get: () => editorBackgroundMenuOpen,
    set: (nextValue) => {
      editorBackgroundMenuOpen = nextValue;
    },
  },
  editorTextColor: {
    get: () => textColorMenuOpen,
    set: (nextValue) => {
      textColorMenuOpen = nextValue;
    },
  },
  editorTextHighlight: {
    get: () => textHighlightMenuOpen,
    set: (nextValue) => {
      textHighlightMenuOpen = nextValue;
    },
  },
  editorBlockStyle: {
    get: () => blockSurfaceMenuOpen,
    set: (nextValue) => {
      blockSurfaceMenuOpen = nextValue;
    },
  },
  editorLineStyle: {
    get: () => lineHighlightMenuOpen,
    set: (nextValue) => {
      lineHighlightMenuOpen = nextValue;
    },
  },
  editorSelectionStyle: {
    get: () => selectionHighlightMenuOpen,
    set: (nextValue) => {
      selectionHighlightMenuOpen = nextValue;
    },
  },
});

function resolveSettingsMenuId(id = "") {
  return settingsMenuAliases[id] ?? id;
}

function closeSettingsMenus(except = "") {
  const resolvedExcept = resolveSettingsMenuId(except);
  Object.entries(settingsMenuControllers).forEach(([menuId, controller]) => {
    controller.set(menuId === resolvedExcept);
  });
  if (resolvedExcept !== "glyphColor") {
    openGlyphColorMenu = null;
  }
}

function toggleSettingsMenu(menuId) {
  const resolvedId = resolveSettingsMenuId(menuId);
  const controller = settingsMenuControllers[resolvedId];
  if (!controller) {
    return;
  }
  closeSettingsMenus(controller.get() ? "" : resolvedId);
  requestSettingsStateRender();
}

function applySettingsOptionSelection(settingId, value) {
  switch (settingId) {
    case "language":
      activeLanguageKey = value;
      closeSettingsMenus();
      persistLanguageState();
      applyLanguageUi();
      flushFullAppRender();
      return;
    case "style":
      activeUiStyleKey = value;
      closeSettingsMenus();
      persistUiStyleState();
      applyUiStyleStrategy();
      flushFullAppRender();
      return;
    case "autoSave":
      autoSaveMode = value;
      closeSettingsMenus();
      clearAutoSaveTimer();
      syncAutoSaveUi();
      persistAutoSaveState();
      if (autoSaveMode === "afterDelay") {
        scheduleAutoSave();
      }
      return;
    case "themePalette":
      closeSettingsMenus();
      selectSurfacePalette(SURFACE_KEYS.THEME, value);
      return;
    case "themeText":
      dispatchSurfaceAction(SURFACE_ACTIONS.THEME_TEXT, () => {
        activeThemeTextKey = value;
      });
      return;
    case "themeColor":
      dispatchSurfaceAction(SURFACE_ACTIONS.THEME_COLOR, () => {
        activeThemeColorKey = value;
      });
      return;
    case "themeBackground":
      dispatchSurfaceAction(SURFACE_ACTIONS.THEME_BACKGROUND, () => {
        activeThemeBackgroundKey = value;
      });
      return;
    case "themeLines":
      dispatchSurfaceAction(SURFACE_ACTIONS.THEME_LINES, () => {
        activeThemeLineKey = value;
      });
      return;
    case "interfaceFont":
      dispatchSurfaceAction(SURFACE_ACTIONS.INTERFACE_FONT, () => {
        activeInterfaceFontKey = value;
      });
      return;
    case "editorFont":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_FONT, () => {
        activeEditorFontKey = value;
      });
      return;
    case "editorPalette":
      closeSettingsMenus();
      selectSurfacePalette(SURFACE_KEYS.EDITOR, value);
      return;
    case "editorBackground":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_BACKGROUND, () => {
        activeEditorBackgroundKey = value;
      });
      return;
    case "editorTextColor":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_TEXT_COLOR, () => {
        activeEditorTextColorKey = value;
      });
      return;
    case "editorTextHighlight":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_TEXT_HIGHLIGHT, () => {
        activeEditorTextHighlightKey = value;
        const preset = editorTextHighlightPresets.find((entry) => entry.key === value);
        if (preset) {
          applySharedGlyphColor(preset.color);
        }
      });
      return;
    case "editorBlockStyle":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_BLOCK_STYLE, () => {
        activeBlockSurfaceKey = value;
      });
      return;
    case "editorLineStyle":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_LINE_STYLE, () => {
        activeLineHighlightKey = value;
      });
      return;
    case "editorSelectionStyle":
      dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_SELECTION_STYLE, () => {
        activeSelectionHighlightKey = value;
      });
      return;
    default:
      return;
  }
}

function handleSettingsDialogAction(actionId) {
  if (actionId === "importThemeConfigButton" || actionId === "importEditorConfigButton") {
    openPaletteConfigImportPicker(workspaceRootPath);
    return;
  }

  if (actionId === "editThemeConfigButton" || actionId === "editEditorConfigButton") {
    openPaletteConfigEditor();
  }
}

function syncSettingsUi() {
  syncLanguageUi();
  syncStyleUi();
  syncAutoSaveUi();
  syncThemeUi();
  syncEditorPreferencesUi();
  syncLinkedSurfaceModeCardUi();
  syncGlyphHighlightUi();
}

function persistGlyphHighlights() {
  try {
    window.localStorage.setItem(
      glyphHighlightStorageKey,
      JSON.stringify({
        editorMode,
        paletteKey: currentEditorPaletteSelectionKey(),
        editorBackgroundKey: activeEditorBackgroundKey,
        editorTextColorKey: activeEditorTextColorKey,
        editorTextHighlightKey: activeEditorTextHighlightKey,
        blockSurfaceKey: activeBlockSurfaceKey,
        lineHighlightKey: activeLineHighlightKey,
        selectionHighlightKey: activeSelectionHighlightKey,
        colors: glyphColors,
      }),
    );
  } catch (error) {
    console.warn("failed to persist glyph highlights", error);
  }
  persistCustomPaletteConfigState();
}

function applyGlyphColors() {
  glyphColorSpecs.forEach((spec) => {
    document.documentElement.style.setProperty(spec.cssVar, glyphColors[spec.key]);
  });
}

function currentEditorModeOptions() {
  return glyphPaletteOptions.filter(
    (palette) => (editorPaletteMeta[palette.key]?.mode ?? "dark") === editorMode,
  );
}

function defaultEditorPaletteForMode(mode) {
  return (
    glyphPaletteOptions.find((palette) => (editorPaletteMeta[palette.key]?.mode ?? "dark") === mode) ??
    glyphPaletteOptions[0]
  );
}

function matchedEditorPalette() {
  return (
    glyphPaletteOptions.find((palette) => {
      const meta = editorPaletteMeta[palette.key] ?? {};
      return (
        (meta.mode ?? "dark") === editorMode &&
        meta.backgroundKey === activeEditorBackgroundKey &&
        meta.textColorKey === activeEditorTextColorKey &&
        meta.textHighlightKey === activeEditorTextHighlightKey &&
        meta.blockKey === activeBlockSurfaceKey &&
        meta.lineKey === activeLineHighlightKey &&
        meta.selectionKey === activeSelectionHighlightKey
      );
    }) ?? null
  );
}

function currentEditorPaletteSelectionKey() {
  return matchedEditorPalette()?.key ?? "customized";
}

function currentEditorPaletteLabel() {
  return matchedEditorPalette()?.label ?? t("customized");
}

function currentPalette() {
  const byKey = glyphPaletteOptions.find((palette) => palette.key === activePaletteKey);
  if (byKey && (editorPaletteMeta[byKey.key]?.mode ?? "dark") === editorMode) {
    return byKey;
  }
  return currentEditorModeOptions()[0] ?? glyphPaletteOptions[0];
}

function currentBlockSurface() {
  return (
    blockSurfacePresets.find((preset) => preset.key === activeBlockSurfaceKey) ?? blockSurfacePresets[0]
  );
}

function currentLineHighlight() {
  return (
    lineHighlightPresets.find((preset) => preset.key === activeLineHighlightKey) ??
    lineHighlightPresets[0]
  );
}

function currentSelectionHighlight() {
  return (
    selectionHighlightPresets.find((preset) => preset.key === activeSelectionHighlightKey) ??
    selectionHighlightPresets[0]
  );
}

function applyEditorTheme() {
  Object.entries(currentPalette().editorTheme).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyBlockSurfaceTheme() {
  Object.entries(currentBlockSurface().vars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
}

function applyLineHighlightTheme() {
  document.documentElement.style.setProperty("--editor-line-selected", currentLineHighlight().value);
}

function applySelectionHighlightTheme() {
  document.documentElement.style.setProperty("--editor-selection", currentSelectionHighlight().value);
}

function applyEditorPaletteSelection(paletteKey) {
  const palette = glyphPaletteOptions.find((entry) => entry.key === paletteKey);
  if (!palette) {
    return;
  }

  const meta = editorPaletteMeta[palette.key] ?? {};
  activePaletteKey = palette.key;
  editorMode = meta.mode ?? editorMode;
  activeEditorBackgroundKey = meta.backgroundKey ?? activeEditorBackgroundKey;
  activeEditorTextColorKey = meta.textColorKey ?? activeEditorTextColorKey;
  activeEditorTextHighlightKey = meta.textHighlightKey ?? activeEditorTextHighlightKey;
  activeBlockSurfaceKey = meta.blockKey ?? activeBlockSurfaceKey;
  activeLineHighlightKey = meta.lineKey ?? activeLineHighlightKey;
  activeSelectionHighlightKey = meta.selectionKey ?? activeSelectionHighlightKey;
  applySharedGlyphColor(palette.color);
}

function syncGlyphHighlightUi() {
  syncDropdownControl({
    nodeId: "editorPalette",
    button: highlightPaletteButton,
    menu: highlightPaletteOptions,
    label: currentEditorPaletteLabel(),
    open: paletteMenuOpen,
    options: currentEditorModeOptions().map((palette) => ({ key: palette.key, label: palette.label })),
    activeKey: currentEditorPaletteSelectionKey(),
  });
  syncDropdownControl({
    nodeId: "editorBlockStyle",
    button: blockSurfaceButton,
    menu: blockSurfaceOptions,
    label: currentBlockSurface().label,
    open: blockSurfaceMenuOpen,
    options: blockSurfacePresets.map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeBlockSurfaceKey,
  });
  syncDropdownControl({
    nodeId: "editorLineStyle",
    button: lineHighlightButton,
    menu: lineHighlightOptions,
    label: currentLineHighlight().label,
    open: lineHighlightMenuOpen,
    options: lineHighlightPresets.map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeLineHighlightKey,
  });
  syncDropdownControl({
    nodeId: "editorSelectionStyle",
    button: selectionHighlightButton,
    menu: selectionHighlightOptions,
    label: currentSelectionHighlight().label,
    open: selectionHighlightMenuOpen,
    options: selectionHighlightPresets.map((preset) => ({ key: preset.key, label: preset.label })),
    activeKey: activeSelectionHighlightKey,
  });

  glyphColorSpecs.forEach((spec) => {
    const color = glyphColors[spec.key].toUpperCase();
    const swatch = glyphColorList.querySelector(`[data-glyph-swatch="${spec.key}"]`);
    const text = glyphColorList.querySelector(`[data-glyph-value="${spec.key}"]`);
    if (swatch) {
      swatch.style.setProperty("--glyph-swatch-color", color);
    }
    if (text) {
      text.value = color;
    }

    const options = glyphColorList.querySelectorAll(`[data-glyph-option-key="${spec.key}"]`);
    options.forEach((button) => {
      const active = button.dataset.glyphOption === color;
      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });

    const toggle = glyphColorList.querySelector(`[data-glyph-toggle="${spec.key}"]`);
    const open = openGlyphColorMenu === spec.key;
    toggle?.classList.toggle("is-open", open);
    toggle?.setAttribute("aria-expanded", String(open));
    glyphColorList
      .querySelector(`[data-glyph-options="${spec.key}"]`)
      ?.classList.toggle("is-open", open);
  });
}

function renderGlyphHighlightControls() {
  if (!glyphColorList) {
    return;
  }

  const glyphDisclosureNode = settingsNodesById.get("symbolHighlightDisclosure");
  glyphColorList.innerHTML = createSettingsNodes(glyphDisclosureNode?.children ?? [], {
    tokens: settingsFactoryTokens,
  });

  syncGlyphHighlightUi();
}

function applySharedGlyphColor(color) {
  glyphColorSpecs.forEach((spec) => {
    glyphColors[spec.key] = color;
  });
}

function loadGlyphHighlightState() {
  try {
    const raw = window.localStorage.getItem(glyphHighlightStorageKey);
    if (!raw) {
      activePaletteKey = glyphPaletteOptions[0].key;
      activeBlockSurfaceKey = blockSurfacePresets[0].key;
      activeLineHighlightKey = lineHighlightPresets[0].key;
      activeSelectionHighlightKey = selectionHighlightPresets[0].key;
      return;
    }

    const parsed = JSON.parse(raw);
    if (parsed?.editorMode === "dark" || parsed?.editorMode === "light") {
      editorMode = parsed.editorMode;
    }
    const requestedPaletteKey = legacyGlyphPaletteKeyMap[parsed?.paletteKey] ?? parsed?.paletteKey;
    activePaletteKey = glyphPaletteOptions.some((palette) => palette.key === requestedPaletteKey)
      ? requestedPaletteKey
      : glyphPaletteOptions[0].key;
    editorMode = editorPaletteMeta[activePaletteKey]?.mode ?? editorMode;
    if (editorBackgroundPresets.some((preset) => preset.key === parsed?.editorBackgroundKey)) {
      activeEditorBackgroundKey = parsed.editorBackgroundKey;
    }
    if (editorTextColorPresets.some((preset) => preset.key === parsed?.editorTextColorKey)) {
      activeEditorTextColorKey = parsed.editorTextColorKey;
    }
    const migratedEditorTextHighlightKey =
      legacyEditorTextHighlightKeyMap[parsed?.editorTextHighlightKey] ?? parsed?.editorTextHighlightKey;
    if (editorTextHighlightPresets.some((preset) => preset.key === migratedEditorTextHighlightKey)) {
      activeEditorTextHighlightKey = migratedEditorTextHighlightKey;
    }
    activeBlockSurfaceKey = blockSurfacePresets.some((preset) => preset.key === parsed?.blockSurfaceKey)
      ? parsed.blockSurfaceKey
      : blockSurfacePresets[0].key;
    activeLineHighlightKey = lineHighlightPresets.some(
      (preset) => preset.key === parsed?.lineHighlightKey,
    )
      ? parsed.lineHighlightKey
      : lineHighlightPresets[0].key;
    activeSelectionHighlightKey = selectionHighlightPresets.some(
      (preset) => preset.key === parsed?.selectionHighlightKey,
    )
      ? parsed.selectionHighlightKey
      : selectionHighlightPresets[0].key;
    const candidateColors = Object.fromEntries(
      glyphColorSpecs.map((spec) => [spec.key, defaultGlyphColor]),
    );
    glyphColorSpecs.forEach((spec) => {
      candidateColors[spec.key] = normalizeHexColor(
        parsed?.colors?.[spec.key] ?? candidateColors[spec.key],
        candidateColors[spec.key],
      );
    });

    glyphColors = candidateColors;
  } catch (error) {
    console.warn("failed to restore glyph highlights", error);
  }
}

function countMatches(value, regex) {
  return (value.match(regex) || []).length;
}

function countChar(value, char) {
  return countMatches(value, new RegExp(`\\${char}`, "g"));
}

function indentUnit() {
  return " ".repeat(indentSize);
}

function padLine(index) {
  return String(index + 1).padStart(2, "0");
}

function splitLines(source) {
  return source.replace(/\r\n/g, "\n").split("\n");
}

function matchBlockHeader(line) {
  const fnMatch = line.match(/^\s*fn\s+([A-Za-z_]\w*)/);
  if (fnMatch) {
    return { type: "fn", title: fnMatch[1], visualStart: "body" };
  }

  const hashMatch = line.match(/^\s*#\s*([A-Za-z_]\w*)?/);
  if (hashMatch) {
    return { type: "hash", title: hashMatch[1] || "hash", visualStart: "header" };
  }

  const atMatch = line.match(/^\s*@\s*([A-Za-z_]\w*)?/);
  if (atMatch) {
    return { type: "at", title: atMatch[1] || "at", visualStart: "header" };
  }

  return null;
}

function findDeferredBlockOpenLine(lines, headerIndex) {
  for (let cursor = headerIndex + 1; cursor < lines.length; cursor += 1) {
    const candidate = lines[cursor];
    if (candidate.trim() === "") {
      continue;
    }

    return candidate.includes("{") ? cursor : null;
  }

  return null;
}

function blockVisualStart(header, headerLine, openLine, closingLine) {
  if (header.visualStart !== "body") {
    return headerLine;
  }

  return Math.min(closingLine, openLine + 1);
}

function findBlocks(lines) {
  const blocks = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const header = matchBlockHeader(line);
    if (!header) {
      continue;
    }

    let openLine = index;
    let depth = 0;

    if (line.includes("{")) {
      depth = countChar(line, "{") - countChar(line, "}");
    } else {
      const deferredOpenLine = findDeferredBlockOpenLine(lines, index);
      if (deferredOpenLine === null) {
        blocks.push({
          type: header.type,
          title: header.title,
          header: index,
          visualStart: index,
          closing: index,
        });
        continue;
      }

      openLine = deferredOpenLine;
      depth = countChar(lines[openLine], "{") - countChar(lines[openLine], "}");
    }

    if (depth <= 0) {
      blocks.push({
        type: header.type,
        title: header.title,
        header: index,
        visualStart: blockVisualStart(header, index, openLine, openLine),
        closing: openLine,
      });
      continue;
    }

    let cursor = openLine + 1;
    while (cursor < lines.length && depth > 0) {
      depth += countChar(lines[cursor], "{") - countChar(lines[cursor], "}");
      if (depth === 0) {
        break;
      }
      cursor += 1;
    }

    if (cursor < lines.length && depth === 0) {
      blocks.push({
        type: header.type,
        title: header.title,
        header: index,
        visualStart: blockVisualStart(header, index, openLine, cursor),
        closing: cursor,
      });
      index = cursor;
    }
  }

  return blocks;
}

function analyzeSource(source) {
  const lines = splitLines(source);
  const glyphCount = countMatches(source, glyphOperatorPattern);
  const blocks = findBlocks(lines);
  const braceBalance = countMatches(source, /{/g) - countMatches(source, /}/g);
  const pipelineName = source.match(/^\s*pipeline\s+([A-Za-z_]\w*)/m)?.[1] || null;
  const functionName = source.match(/^\s*fn\s+([A-Za-z_]\w*)/m)?.[1] || null;
  const warnings = [];
  const errors = [];

  const betaIndex = lines.findIndex((line) => line.includes("spawn worker.beta"));
  if (betaIndex !== -1 && !source.includes("joined(")) {
    warnings.push({
      lineIndex: betaIndex,
      title: `line ${padLine(betaIndex)} / join strategy`,
      body: "worker.beta exists but no explicit join strategy is declared.",
    });
  }

  if (braceBalance !== 0) {
    errors.push({
      lineIndex: Math.max(0, lines.findIndex((line) => /^\s*fn\s+/.test(line))),
      title: "semantic block incomplete",
      body: "the current function body is not closed, so the minimal unit is not ready.",
    });
  }

  const selectedLineIndex =
    errors[0]?.lineIndex ??
    warnings[0]?.lineIndex ??
    Math.max(0, lines.findIndex((line) => /^\s*fn\s+/.test(line)) + 1);

  const lineStarts = [];
  let cursor = 0;
  lines.forEach((line, index) => {
    lineStarts[index] = cursor;
    cursor += line.length;
    if (index < lines.length - 1) {
      cursor += 1;
    }
  });

  return {
    lines,
    lineStarts,
    glyphCount,
    blocks,
    warnings,
    errors,
    selectedLineIndex,
    pipelineName,
    functionName,
    ready: Boolean(functionName) && braceBalance === 0,
  };
}

function renderToken(token) {
  const glyph = operatorGlyphs[token];
  if (!glyph) {
    return escapeHtml(token);
  }

  const visualMarkup = glyph.markup ?? escapeHtml(glyph.visual);
  return `<span class="token ${glyph.tokenClass}"><span class="token-visual">${visualMarkup}</span><span class="token-raw">${escapeHtml(token)}</span></span>`;
}

function isKeywordChar(char) {
  return /[\p{L}\p{N}_]/u.test(char);
}

function findKeywordTokenAt(line, index) {
  const current = line[index] ?? "";
  if (!isKeywordChar(current)) {
    return null;
  }

  if (index > 0 && isKeywordChar(line[index - 1] ?? "")) {
    return null;
  }

  let end = index + 1;
  while (end < line.length && isKeywordChar(line[end] ?? "")) {
    end += 1;
  }

  const lexeme = line.slice(index, end);
  return styioHighlightKeywords.has(lexeme) ? lexeme : null;
}

function renderKeywordToken(token) {
  return `<span class="token-keyword">${escapeHtml(token)}</span>`;
}

function findGlyphTokenAt(line, index) {
  return glyphOperators.find((token) => line.startsWith(token, index)) ?? null;
}

function renderInlineWithCaret(line, lineStart, caretOffset) {
  let html = "";
  let index = 0;

  while (index < line.length) {
    const token = findGlyphTokenAt(line, index);
    const keyword = !token ? findKeywordTokenAt(line, index) : null;
    const tokenStart = lineStart + index;
    const insideToken =
      token !== null && caretOffset > tokenStart && caretOffset < tokenStart + token.length;

    if (token && !insideToken) {
      html += renderToken(token);
      index += token.length;
      continue;
    }

    if (keyword) {
      html += renderKeywordToken(keyword);
      index += keyword.length;
      continue;
    }

    html += escapeHtml(line[index]);
    index += 1;
  }

  return html;
}

function renderLineWithSelection(line, lineStart, caretOffset, selectionStart, selectionEnd) {
  if (selectionStart === selectionEnd) {
    return renderInlineWithCaret(line, lineStart, caretOffset);
  }

  const lineEnd = lineStart + line.length;
  const overlapStart = Math.max(lineStart, selectionStart);
  const overlapEnd = Math.min(lineEnd, selectionEnd);

  if (overlapStart >= overlapEnd) {
    if (line.length === 0 && selectionStart <= lineStart && selectionEnd > lineStart) {
      return `<span class="selection-fragment selection-fragment-empty">&nbsp;</span>`;
    }

    return renderInlineWithCaret(line, lineStart, caretOffset);
  }

  const before = line.slice(0, overlapStart - lineStart);
  const selected = line.slice(overlapStart - lineStart, overlapEnd - lineStart);
  const after = line.slice(overlapEnd - lineStart);

  return [
    renderInlineWithCaret(before, lineStart, caretOffset),
    `<span class="selection-fragment">${escapeHtml(selected)}</span>`,
    renderInlineWithCaret(after, overlapEnd, caretOffset),
  ].join("");
}

function measureHtmlWidth(html) {
  measureLine.innerHTML = `<span class="code-text">${html}</span>`;
  return measureLine.getBoundingClientRect().width;
}

function getCaretCoordinates(line, lineStart, rawOffset) {
  const relativeOffset = Math.max(0, Math.min(line.length, rawOffset - lineStart));
  const prefix = line.slice(0, relativeOffset);
  const prefixHtml = renderInlineWithCaret(prefix, lineStart, rawOffset);
  const lineBoxPadX = getCssNumber("--editor-line-box-pad-x");
  return {
    x: lineBoxPadX + measureHtmlWidth(prefixHtml),
    rawOffset: lineStart + relativeOffset,
  };
}

function findRawOffsetForX(line, lineStart, targetX) {
  let best = { distance: Number.POSITIVE_INFINITY, rawOffset: lineStart };

  for (let index = 0; index <= line.length; index += 1) {
    const { x, rawOffset } = getCaretCoordinates(line, lineStart, lineStart + index);
    const distance = Math.abs(x - targetX);
    if (distance < best.distance) {
      best = { distance, rawOffset };
    }
  }

  return best.rawOffset;
}

function lineIndexForOffset(analysis, rawOffset) {
  const normalizedOffset = Math.max(0, Math.min(editorInput.value.length, rawOffset));
  let lineIndex = analysis.lineStarts.findIndex((start, index) => {
    const end = start + analysis.lines[index].length;
    return normalizedOffset >= start && normalizedOffset <= end;
  });

  if (lineIndex === -1) {
    lineIndex = analysis.lines.length - 1;
  }

  return Math.max(0, lineIndex);
}

function rawOffsetForPointer(event, analysis) {
  const stageRect = codeStage.getBoundingClientRect();
  const padY = getCssNumber("--editor-pad-y");
  const padX = getCssNumber("--editor-pad-x");
  const lineHeight = getCssNumber("--editor-line-height");
  const localY = event.clientY - stageRect.top + editorInput.scrollTop - padY;
  const localX = event.clientX - stageRect.left + editorInput.scrollLeft - padX;
  const lineIndex = Math.max(
    0,
    Math.min(analysis.lines.length - 1, Math.floor(localY / lineHeight)),
  );
  const lineText = analysis.lines[lineIndex];
  const lineStart = analysis.lineStarts[lineIndex];
  return findRawOffsetForX(lineText, lineStart, Math.max(0, localX));
}

function characterOffsetForPointer(event, analysis) {
  const stageRect = codeStage.getBoundingClientRect();
  const padY = getCssNumber("--editor-pad-y");
  const padX = getCssNumber("--editor-pad-x");
  const lineHeight = getCssNumber("--editor-line-height");
  const localY = event.clientY - stageRect.top + editorInput.scrollTop - padY;
  const localX = event.clientX - stageRect.left + editorInput.scrollLeft - padX;
  const lineIndex = Math.max(
    0,
    Math.min(analysis.lines.length - 1, Math.floor(localY / lineHeight)),
  );
  const lineText = analysis.lines[lineIndex];
  const lineStart = analysis.lineStarts[lineIndex];

  if (!lineText.length) {
    return lineStart;
  }

  const targetX = Math.max(0, localX);
  for (let index = 0; index < lineText.length; index += 1) {
    const next = getCaretCoordinates(lineText, lineStart, lineStart + index + 1).x;
    if (targetX < next) {
      return lineStart + index;
    }
  }

  return lineStart + lineText.length - 1;
}

function classifySelectionChar(char) {
  if (!char) {
    return "none";
  }
  if (/\s/.test(char)) {
    return "whitespace";
  }
  if (/[\p{L}\p{N}_]/u.test(char)) {
    return "word";
  }
  return "symbol";
}

function wordSelectionRangeForOffset(value, rawOffset) {
  if (!value.length) {
    return { start: 0, end: 0 };
  }

  const clampedOffset = Math.max(0, Math.min(value.length, rawOffset));
  const rightChar = value[clampedOffset] ?? "";
  const leftChar = clampedOffset > 0 ? value[clampedOffset - 1] ?? "" : "";

  let anchorIndex = clampedOffset;
  let selectionKind = classifySelectionChar(rightChar);

  if (selectionKind === "none" || selectionKind === "whitespace") {
    const leftKind = classifySelectionChar(leftChar);
    if (leftKind !== "none" && leftKind !== "whitespace") {
      anchorIndex = clampedOffset - 1;
      selectionKind = leftKind;
    }
  }

  if (selectionKind === "none" || selectionKind === "whitespace") {
    return { start: clampedOffset, end: clampedOffset };
  }

  let start = anchorIndex;
  let end = anchorIndex + 1;

  while (start > 0 && classifySelectionChar(value[start - 1]) === selectionKind) {
    start -= 1;
  }

  while (end < value.length && classifySelectionChar(value[end]) === selectionKind) {
    end += 1;
  }

  return { start, end };
}

function lineSelectionRangeForOffset(value, rawOffset) {
  const clampedOffset = Math.max(0, Math.min(value.length, rawOffset));
  const lineStart = currentLineStart(value, clampedOffset);
  const lineEnd = currentLineEnd(value, clampedOffset);
  const terminalEnd = lineEnd < value.length ? lineEnd + 1 : lineEnd;
  return { start: lineStart, end: terminalEnd };
}

function setSelectionFromAnchor(anchor, focus) {
  if (focus < anchor) {
    editorInput.setSelectionRange(focus, anchor, "backward");
    return;
  }

  editorInput.setSelectionRange(anchor, focus, "forward");
}

function selectedSourceText() {
  const { start, end } = normalizedSelectionRange();
  return editorInput.value.slice(start, end);
}

function stopPointerSelection() {
  pointerSelectionAnchor = null;
  if (pointerSelectionCleanup) {
    pointerSelectionCleanup();
    pointerSelectionCleanup = null;
  }
}

function scheduleNativeRender() {
  requestRender(renderGroups.editorSelection);
}

function scheduleLayoutRender() {
  requestRender(renderGroups.editorLayout);
  window.requestAnimationFrame(() => {
    requestRender(renderGroups.editorLayout);
  });
  if (pendingLayoutRenderTimeout) {
    window.clearTimeout(pendingLayoutRenderTimeout);
  }
  pendingLayoutRenderTimeout = window.setTimeout(() => {
    pendingLayoutRenderTimeout = 0;
    requestRender(renderGroups.editorLayout);
  }, 260);
}

function ensureGridLayoutConfigBinding() {
  if (detachGridLayoutConfigBinding || !document.body) {
    return;
  }

  detachGridLayoutConfigBinding = bindGridLayoutConfigTarget(document.body, {
    onAfterApply: () => {
      if (document.body.dataset.uiStyle === "grid") {
        scheduleLayoutRender();
      }
    },
  });
}

function syncSidebar() {
  document.body.classList.toggle("sidebar-open", sidebarOpen);
  workspaceShell.classList.toggle("sidebar-open", sidebarOpen);
  syncStyleShellLayout(styleShellBridge, {
    activeUiStyleKey,
    sidebarOpen,
    toggleIconMarkup: sidebarToggleSvg(false),
    closeIconMarkup: sidebarToggleSvg(false),
    t,
  });

  drawerTabs.forEach((button) => {
    const active = button.dataset.drawerTab === activeDrawerTab;
    button.classList.toggle("is-active", active);
    const panel = document.getElementById(`drawerPanel${button.dataset.drawerTab.charAt(0).toUpperCase()}${button.dataset.drawerTab.slice(1)}`);
    panel.classList.toggle("is-active", active);
  });

  scheduleLayoutRender();
}

function chooseWorkspaceFile(preferredFile, files) {
  if (preferredFile && files.includes(preferredFile)) {
    return preferredFile;
  }
  if (files.includes(primaryFile)) {
    return primaryFile;
  }
  const styioFile = files.find((filePath) => filePath.endsWith(".styio"));
  if (styioFile) {
    return styioFile;
  }
  return files[0] ?? primaryFile;
}

function collectTreePaths(entries, bucket = new Set()) {
  entries.forEach((entry) => {
    if (!entry?.path) {
      return;
    }
    bucket.add(entry.path);
    if (entry.type === "directory" && Array.isArray(entry.children)) {
      collectTreePaths(entry.children, bucket);
    }
  });
  return bucket;
}

function collectDirectoryPaths(entries, bucket = new Set()) {
  entries.forEach((entry) => {
    if (!entry?.path || entry.type !== "directory") {
      return;
    }
    bucket.add(entry.path);
    if (Array.isArray(entry.children)) {
      collectDirectoryPaths(entry.children, bucket);
    }
  });
  return bucket;
}

function normalizeDeleteSelection(paths) {
  const normalized = Array.from(new Set((paths || []).map((path) => String(path || "").trim()).filter(Boolean))).sort();
  return normalized.filter((candidate, index) => {
    return !normalized.some((other, otherIndex) => {
      if (index === otherIndex) {
        return false;
      }
      return candidate.startsWith(`${other}/`);
    });
  });
}

function findTreeEntryByPath(entries, targetPath) {
  for (const entry of entries || []) {
    if (entry?.path === targetPath) {
      return entry;
    }
    if (entry?.type === "directory") {
      const nested = findTreeEntryByPath(entry.children || [], targetPath);
      if (nested) {
        return nested;
      }
    }
  }
  return null;
}

function activeTreeEntry() {
  if (!activeTreePath) {
    return null;
  }
  if (activeTreePath === currentFile && !workspaceEntries.length) {
    return { type: "file", path: currentFile, name: currentFile.split("/").pop() || currentFile };
  }
  return findTreeEntryByPath(workspaceEntries, activeTreePath);
}

function parentDirectoryOf(path) {
  const index = String(path || "").lastIndexOf("/");
  return index >= 0 ? path.slice(0, index) : "";
}

function formatTabFileLabel(path) {
  const baseName = String(path || "").split("/").pop() || String(path || "");
  const extensionIndex = baseName.lastIndexOf(".");
  return extensionIndex > 0 ? baseName.slice(0, extensionIndex) : baseName;
}

function joinRelativePath(basePath, leafName) {
  return basePath ? `${basePath}/${leafName}` : leafName;
}

function normalizeWorkspaceDraftPath(rawPath) {
  return String(rawPath || "")
    .trim()
    .replace(/^(?:(?:\.\/)|\/)+/, "");
}

function formatWorkspaceDraftPath(rawPath) {
  const normalizedPath = normalizeWorkspaceDraftPath(rawPath);
  return normalizedPath ? `./${normalizedPath}` : "./";
}

function resolveCreationBasePath() {
  const entry = activeTreeEntry();
  if (!entry) {
    return "";
  }
  if (entry.type === "directory") {
    return entry.path;
  }
  return parentDirectoryOf(entry.path);
}

function defaultCreateTarget(kind) {
  const leafName = defaultCreateLeafNames[kind];
  const basePath = resolveCreationBasePath();
  const targetPath = basePath ? joinRelativePath(basePath, leafName) : leafName;
  return formatWorkspaceDraftPath(targetPath);
}

function isTreePathSelected(path) {
  return selectedTreePaths.has(path);
}

function clearBulkDeleteSelection() {
  selectedTreePaths = new Set();
}

function exitBulkDeleteMode() {
  bulkDeleteMode = false;
  clearBulkDeleteSelection();
}

function syncBulkDeleteButton() {
  if (!bulkDeleteButton) {
    return;
  }

  const selectedCount = selectedTreePaths.size;
  bulkDeleteButton.classList.toggle("is-active", bulkDeleteMode);
  bulkDeleteButton.classList.toggle("has-selection", bulkDeleteMode && selectedCount > 0);
  bulkDeleteButton.setAttribute("aria-pressed", String(bulkDeleteMode));

  if (!bulkDeleteMode) {
    const activeEntry = activeTreeEntry();
    if (activeEntry) {
      const label = t("deleteActiveEntry", { name: activeEntry.name });
      bulkDeleteButton.setAttribute("aria-label", label);
      bulkDeleteButton.setAttribute("title", label);
      return;
    }
    bulkDeleteButton.setAttribute("aria-label", t("selectFilesToDelete"));
    bulkDeleteButton.setAttribute("title", t("selectFilesToDelete"));
    return;
  }

  if (selectedCount > 0) {
    const label = t("deleteSelectedItems", {
      count: selectedCount,
      suffix: selectedCount > 1 ? "s" : "",
    });
    bulkDeleteButton.setAttribute("aria-label", label);
    bulkDeleteButton.setAttribute("title", label);
    return;
  }

  bulkDeleteButton.setAttribute("aria-label", t("exitDeleteSelection"));
  bulkDeleteButton.setAttribute("title", t("exitDeleteSelection"));
}

function syncRefreshWorkspaceButton() {
  if (!refreshWorkspaceButton) {
    return;
  }

  refreshWorkspaceButton.classList.toggle("is-cancel-mode", bulkDeleteMode);
  refreshWorkspaceButton.innerHTML = bulkDeleteMode ? cancelSelectionSvg : refreshWorkspaceSvg;
  const label = bulkDeleteMode ? t("cancelMultiSelect") : t("refreshWorkspace");
  refreshWorkspaceButton.setAttribute("aria-label", label);
  refreshWorkspaceButton.setAttribute("title", label);
}

function currentLanguageOption() {
  return languageOptionsList.find((option) => option.key === activeLanguageKey) ?? languageOptionsList[0];
}

function currentUiStyleOption() {
  return uiStyleOptionsList.find((option) => option.key === activeUiStyleKey) ?? uiStyleOptionsList[0];
}

function applyUiStyleStrategy() {
  const styleFactory = createUiStyleFactory(activeUiStyleKey, settingsFactoryTokens);
  Object.entries(styleFactory.cssVars).forEach(([cssVar, value]) => {
    document.documentElement.style.setProperty(cssVar, value);
  });
  document.body.dataset.uiStyle = styleFactory.key;
  document.body.dataset.themeMode = themeMode;
  document.body.dataset.editorMode = editorMode;
  syncStyleShellLayout(styleShellBridge, {
    activeUiStyleKey: styleFactory.key,
    sidebarOpen,
    toggleIconMarkup: sidebarToggleSvg(false),
    closeIconMarkup: sidebarToggleSvg(false),
    t,
  });
  settingsFactoryRoot?.setAttribute("style", serializeSettingsFactoryTokens(styleFactory.settingsTokens));
  applyVisualTokenOverrides(visualTokenOverrides, {
    root: document.documentElement,
    settingsRoot: settingsFactoryRoot,
  });
}

function persistUiStyleState() {
  try {
    window.localStorage.setItem(storageKeys.uiStyle, JSON.stringify({ style: activeUiStyleKey }));
  } catch (error) {
    console.warn("failed to persist ui style state", error);
  }
  persistCustomPaletteConfigState();
}

function loadUiStyleState() {
  try {
    const raw = window.localStorage.getItem(storageKeys.uiStyle);
    if (!raw) {
      return;
    }
    const parsed = JSON.parse(raw);
    const migratedStyleKey = legacyUiStyleKeyMap[parsed?.style] ?? parsed?.style;
    if (uiStyleOptionsList.some((option) => option.key === migratedStyleKey)) {
      activeUiStyleKey = migratedStyleKey;
    }
  } catch (error) {
    console.warn("failed to restore ui style state", error);
  }
}

function renderSettingsOptionButtons(nodeId, options) {
  return options
    .map(
      (option) => `
        <button
          class="palette-option"
          type="button"
          data-setting-option-for="${nodeId}"
          data-setting-option-value="${option.key}"
        >
          ${option.label}
        </button>
      `,
    )
    .join("");
}

function syncDropdownControl({ nodeId, button, menu, label, open, options, activeKey }) {
  if (button) {
    button.textContent = label;
    button.setAttribute("aria-expanded", String(open));
  }

  if (!menu) {
    return;
  }

  menu.classList.toggle("is-open", open);
  menu.innerHTML = renderSettingsOptionButtons(nodeId, options);
  menu.querySelectorAll("[data-setting-option-value]").forEach((optionButton) => {
    const active = optionButton.dataset.settingOptionValue === activeKey;
    optionButton.classList.toggle("is-active", active);
    optionButton.setAttribute("aria-pressed", String(active));
  });
}

function syncLanguageUi() {
  syncDropdownControl({
    nodeId: "language",
    button: languageModeButton,
    menu: languageModeOptions,
    label: currentLanguageOption().label,
    open: languageMenuOpen,
    options: languageOptionsList,
    activeKey: activeLanguageKey,
  });
}

function renderLanguageOptions() {
  syncLanguageUi();
}

function syncStyleUi() {
  syncDropdownControl({
    nodeId: "style",
    button: styleButton,
    menu: styleOptions,
    label: currentUiStyleOption().label,
    open: styleMenuOpen,
    options: uiStyleOptionsList,
    activeKey: activeUiStyleKey,
  });
}

function renderStyleOptions() {
  syncStyleUi();
}

function currentAutoSaveOption() {
  return autoSaveModeOptionsList.find((option) => option.key === autoSaveMode) ?? autoSaveModeOptionsList[0];
}

function clearAutoSaveTimer() {
  if (autoSaveTimer !== null) {
    window.clearTimeout(autoSaveTimer);
    autoSaveTimer = null;
  }
}

function persistAutoSaveState() {
  try {
    window.localStorage.setItem(
      autoSaveStorageKey,
      JSON.stringify({
        mode: autoSaveMode,
        delay: autoSaveDelay,
      }),
    );
  } catch (error) {
    console.warn("failed to persist auto save state", error);
  }
}

function loadAutoSaveState() {
  try {
    const raw = window.localStorage.getItem(autoSaveStorageKey);
    if (!raw) {
      return;
    }

    const parsed = JSON.parse(raw);
    if (autoSaveModeOptionsList.some((option) => option.key === parsed?.mode)) {
      autoSaveMode = parsed.mode;
    }
    const nextDelay = Number(parsed?.delay);
    if (Number.isFinite(nextDelay) && nextDelay >= 250) {
      autoSaveDelay = Math.round(nextDelay / 250) * 250;
    }
  } catch (error) {
    console.warn("failed to restore auto save state", error);
  }
}

function syncAutoSaveUi() {
  const labelMap = {
    off: activeLanguageKey === "zhCn" ? "关闭" : "Off",
    afterDelay: activeLanguageKey === "zhCn" ? "延迟后" : "After Delay",
    onFocusChange: activeLanguageKey === "zhCn" ? "焦点切换时" : "On Focus Change",
    onWindowChange: activeLanguageKey === "zhCn" ? "窗口切换时" : "On Window Change",
  };
  syncDropdownControl({
    nodeId: "autoSave",
    button: autoSaveModeButton,
    menu: autoSaveModeOptions,
    label: labelMap[autoSaveMode] ?? currentAutoSaveOption().label,
    open: autoSaveMenuOpen,
    options: autoSaveModeOptionsList.map((option) => ({
      key: option.key,
      label: labelMap[option.key] ?? option.label,
    })),
    activeKey: autoSaveMode,
  });

  if (autoSaveDelayField) {
    autoSaveDelayField.hidden = autoSaveMode !== "afterDelay";
  }

  if (autoSaveDelayInput) {
    autoSaveDelayInput.value = String(autoSaveDelay);
  }

  if (autoSaveState) {
    if (autoSaveMode === "off") {
      autoSaveState.textContent = activeLanguageKey === "zhCn" ? "自动保存：关闭" : "autosave: off";
    } else if (autoSaveMode === "afterDelay") {
      autoSaveState.textContent =
        activeLanguageKey === "zhCn" ? `自动保存：${autoSaveDelay}ms 后` : `autosave: after ${autoSaveDelay}ms`;
    } else if (autoSaveMode === "onFocusChange") {
      autoSaveState.textContent =
        activeLanguageKey === "zhCn" ? "自动保存：焦点切换时" : "autosave: on focus change";
    } else {
      autoSaveState.textContent =
        activeLanguageKey === "zhCn" ? "自动保存：窗口切换时" : "autosave: on window change";
    }
  }
}

function renderAutoSaveOptions() {
  syncAutoSaveUi();
}

function triggerAutoSave(reason = "") {
  if (autoSaveMode === "off" || !workspaceApiAvailable || saveInFlight || !fileDirty[currentFile]) {
    return;
  }

  clearAutoSaveTimer();
  void saveCurrentFile(reason);
}

function scheduleAutoSave() {
  clearAutoSaveTimer();
  if (autoSaveMode !== "afterDelay" || !workspaceApiAvailable || saveInFlight || !fileDirty[currentFile]) {
    return;
  }

  autoSaveTimer = window.setTimeout(() => {
    autoSaveTimer = null;
    triggerAutoSave("after-delay");
  }, autoSaveDelay);
}

function closeAppDialog(result = null) {
  if (appDialogOverlay.hidden) {
    return;
  }

  appDialogOverlay.hidden = true;
  const resolver = activeDialogResolver;
  activeDialogResolver = null;
  appDialogInput.value = "";
  appDialogTextarea.value = "";
  if (resolver) {
    resolver(result);
  }
}

function openAppDialog(options = {}) {
  const {
    title = t("dialog"),
    message = "",
    confirmLabel = t("confirm"),
    cancelLabel = t("cancel"),
    input = null,
    textarea = null,
    items = [],
    placeholder = "",
    destructive = false,
  } = options;

  if (activeDialogResolver) {
    activeDialogResolver(null);
    activeDialogResolver = null;
  }

  appDialogTitle.hidden = !title;
  appDialogTitle.textContent = title || t("dialog");
  appDialogMessage.textContent = message;
  appDialogMessage.classList.toggle("is-danger", destructive);
  appDialogConfirm.textContent = confirmLabel;
  appDialogCancel.textContent = cancelLabel;
  appDialogConfirm.classList.toggle("danger", destructive);

  const hasInput = input !== null;
  const hasTextarea = textarea !== null;
  appDialogInputField.hidden = !hasInput;
  appDialogInput.value = hasInput ? String(input) : "";
  appDialogInput.placeholder = placeholder;
  appDialogInput.setAttribute("aria-label", title);
  appDialogTextareaField.hidden = !hasTextarea;
  appDialogTextarea.value = hasTextarea ? String(textarea) : "";
  appDialogTextarea.placeholder = placeholder;
  appDialogTextarea.setAttribute("aria-label", title);

  const dialogItems = Array.isArray(items) ? items.filter(Boolean) : [];
  appDialogList.hidden = dialogItems.length === 0;
  appDialogList.innerHTML = dialogItems
    .map(
      (item) => `
        <div class="app-dialog-list-item">
          <span class="app-dialog-list-path">${escapeHtml(String(item))}</span>
        </div>
      `,
    )
    .join("");

  appDialogOverlay.hidden = false;

  requestAnimationFrame(() => {
    if (hasTextarea) {
      appDialogTextarea.focus();
      appDialogTextarea.setSelectionRange(appDialogTextarea.value.length, appDialogTextarea.value.length);
    } else if (hasInput) {
      appDialogInput.focus();
      appDialogInput.select();
    } else {
      appDialogConfirm.focus();
    }
  });

  return new Promise((resolve) => {
    activeDialogResolver = resolve;
  });
}

function openPromptDialog(options = {}) {
  return openAppDialog({
    ...options,
    input: options.input ?? "",
  });
}

function openTextareaDialog(options = {}) {
  return openAppDialog({
    ...options,
    textarea: options.textarea ?? "",
  });
}

function openConfirmDialog(options = {}) {
  return openAppDialog({
    ...options,
    input: null,
  });
}

function hideAppToast() {
  if (!appToast) {
    return;
  }
  appToast.hidden = true;
  appToast.classList.remove("is-success", "is-error");
  if (appToastTimer) {
    clearTimeout(appToastTimer);
    appToastTimer = null;
  }
}

function showAppToast(message, kind = "success") {
  if (!appToast || !appToastText || !message) {
    return;
  }

  if (appToastTimer) {
    clearTimeout(appToastTimer);
    appToastTimer = null;
  }

  appToastText.textContent = message;
  appToast.hidden = false;
  appToast.classList.toggle("is-success", kind === "success");
  appToast.classList.toggle("is-error", kind === "error");

  appToastTimer = window.setTimeout(() => {
    hideAppToast();
  }, 2200);
}

function setWorkspacePickerMessage(text) {
  workspacePickerCaption.textContent = text;
}

function setWorkspacePickerState({
  mode = "directory",
  includeFiles = false,
  title = t("openWorkspaceTitle"),
  caption = t("chooseWorkspaceRoot"),
  confirmLabel = t("useThisFolder"),
  onConfirm = null,
} = {}) {
  workspacePickerMode = mode;
  workspacePickerIncludeFiles = includeFiles;
  workspacePickerSelectedFilePath = "";
  workspacePickerConfirmAction = onConfirm;
  workspacePickerTitleText = title;
  workspacePickerDefaultCaptionText = caption;
  workspacePickerConfirmText = confirmLabel;
  workspacePickerTitle.textContent = title;
  workspacePickerCaption.textContent = caption;
  workspacePickerConfirm.textContent = confirmLabel;
}

function syncWorkspacePathVisual() {
  if (!workspacePathViewport || !workspacePathScrollVisual || !workspacePathScrollThumb || !workspacePathText) {
    return;
  }

  const viewportWidth = workspacePathViewport.clientWidth;
  const contentWidth = workspacePathText.scrollWidth;
  const trackWidth = workspacePathScrollVisual.clientWidth;
  const maxScroll = Math.max(0, contentWidth - viewportWidth);

  if (!trackWidth) {
    return;
  }

  if (maxScroll <= 0) {
    workspacePathScrollThumb.style.width = `${trackWidth}px`;
    workspacePathScrollThumb.style.transform = "translateX(0px)";
    workspacePathScrollVisual.classList.add("is-static");
    return;
  }

  workspacePathScrollVisual.classList.remove("is-static");
  const thumbWidth = Math.max(28, Math.round((viewportWidth / contentWidth) * trackWidth));
  const maxThumbTravel = Math.max(0, trackWidth - thumbWidth);
  const thumbX = maxThumbTravel > 0 ? (workspacePathViewport.scrollLeft / maxScroll) * maxThumbTravel : 0;
  workspacePathScrollThumb.style.width = `${thumbWidth}px`;
  workspacePathScrollThumb.style.transform = `translateX(${thumbX}px)`;
}

function syncWorkspacePathScrollerMetrics() {
  if (!workspacePathViewport || !workspacePathText) {
    return;
  }

  window.requestAnimationFrame(() => {
    workspacePathViewport.scrollLeft = 0;
    syncWorkspacePathVisual();
  });
}

function scrollWorkspacePathDisplayToStart() {
  syncWorkspacePathScrollerMetrics();
}

function syncWorkspaceControls() {
  if (workspacePathText) {
    workspacePathText.textContent = workspaceRootPath;
  }

  if (workspacePathDisplay) {
    workspacePathDisplay.title = workspaceRootPath;
  }

  scrollWorkspacePathDisplayToStart();

  if (workspacePathHint) {
    workspacePathHint.hidden = true;
    workspacePathHint.textContent = "";
  }

  if (workspaceCallout) {
    workspaceCallout.hidden = true;
  }
}

function renderFileTabs() {
  if (!fileTabs) {
    return;
  }

  fileTabs.innerHTML = fileOrder
    .map((fileName) => {
      const dirty = Boolean(fileDirty[fileName]);
      const tabLabel = formatTabFileLabel(fileName);
      return `
        <div class="editor-tab ${fileName === currentFile ? "is-active" : ""} ${dirty ? "is-dirty" : ""}" data-tab-item="${escapeHtml(fileName)}">
          <button class="editor-tab-main" data-tab-file="${escapeHtml(fileName)}" type="button">
            <span class="editor-tab-label">${escapeHtml(tabLabel)}</span>
          </button>
          <button class="editor-tab-close" data-tab-close="${escapeHtml(fileName)}" type="button" aria-label="${escapeHtml(`${activeLanguageKey === "zhCn" ? "关闭 " : "Close "}${fileName}`)}" title="${escapeHtml(activeLanguageKey === "zhCn" ? "关闭标签页" : "Close tab")}">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M18 6 6 18"></path>
              <path d="m6 6 12 12"></path>
            </svg>
          </button>
        </div>
      `;
    })
    .join("");
}

function renderTreeEntries(entries, depth = 0) {
  return entries
    .map((entry) => {
      if (entry.type === "directory") {
        const directorySelected = isTreePathSelected(entry.path);
        const directoryActive = activeTreePath === entry.path;
        const directoryExpanded = expandedTreePaths.has(entry.path);
        const selectVerb = directorySelected
          ? activeLanguageKey === "zhCn"
            ? "取消选择"
            : "Deselect"
          : activeLanguageKey === "zhCn"
            ? "选择"
            : "Select";
        return `
          <details class="tree-folder ${bulkDeleteMode ? "is-bulk-delete-mode" : ""} ${directorySelected ? "is-bulk-selected" : ""} ${directoryActive ? "is-tree-active" : ""}" data-tree-folder-path="${escapeHtml(entry.path)}" ${directoryExpanded ? "open" : ""} style="--tree-depth:${depth}">
            <summary class="tree-folder-summary" data-tree-folder="${escapeHtml(entry.path)}">
              <div class="tree-folder-leading">
                ${
                  bulkDeleteMode
                    ? `
                      <button class="tree-select-toggle ${directorySelected ? "is-selected" : ""}" data-select-tree-path="${escapeHtml(entry.path)}" type="button" aria-label="${escapeHtml(`${selectVerb} ${entry.name}`)}" title="${escapeHtml(`${selectVerb} ${entry.name}`)}">
                        <span class="tree-select-dot" aria-hidden="true"></span>
                      </button>
                    `
                    : ""
                }
                <span class="tree-folder-name">${escapeHtml(entry.name)}</span>
              </div>
            </summary>
            <div class="tree-folder-children">${renderTreeEntries(entry.children || [], depth + 1)}</div>
          </details>
        `;
      }

      const fileName = entry.path;
      const source = typeof fileSources[fileName] === "string" ? fileSources[fileName] : "";
      const analysis = analyzeSource(source);
      const dirty = Boolean(fileDirty[fileName]);
      const issueCount = source ? analysis.warnings.length + analysis.errors.length : 0;
      let badgeText = "";
      let badgeClass = "";

      if (dirty) {
        badgeText = "dirty";
        badgeClass = "is-dirty";
      } else if (issueCount > 0) {
        badgeText = String(issueCount);
        badgeClass = "has-issues";
      }

      const fileSelected = isTreePathSelected(fileName);
      const fileActive = activeTreePath === fileName;
      const selectVerb = fileSelected
        ? activeLanguageKey === "zhCn"
          ? "取消选择"
          : "Deselect"
        : activeLanguageKey === "zhCn"
          ? "选择"
          : "Select";

      return `
        <div class="tree-file-card ${fileActive ? "is-tree-active" : ""} ${bulkDeleteMode ? "is-bulk-delete-mode" : ""} ${fileSelected ? "is-bulk-selected" : ""}" style="--tree-depth:${depth}">
          <div class="tree-file-head">
            ${
              bulkDeleteMode
                ? `
                  <button class="tree-select-toggle ${fileSelected ? "is-selected" : ""}" data-select-tree-path="${escapeHtml(fileName)}" type="button" aria-label="${escapeHtml(`${selectVerb} ${entry.name}`)}" title="${escapeHtml(`${selectVerb} ${entry.name}`)}">
                    <span class="tree-select-dot" aria-hidden="true"></span>
                  </button>
                `
                : ""
            }
            <button class="tree-file" data-tree-file="${escapeHtml(fileName)}" type="button">
              <div class="tree-copy">
                <span class="tree-name">${escapeHtml(entry.name)}</span>
              </div>
              ${badgeText ? `<span class="tree-badge ${badgeClass}">${badgeText}</span>` : ""}
            </button>
            ${
              bulkDeleteMode
                ? `
                  <button class="tree-preview-button" data-preview-file="${escapeHtml(fileName)}" type="button" aria-label="${escapeHtml(`${t("previewFile")} ${entry.name}`)}" title="${escapeHtml(t("previewFile"))}">
                    <svg viewBox="0 0 24 24" aria-hidden="true">
                      <path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"></path>
                      <circle cx="12" cy="12" r="3"></circle>
                    </svg>
                  </button>
                `
                : ""
            }
          </div>
        </div>
      `;
    })
    .join("");
}

function renderFileTree() {
  if (!workspaceEntries.length && !fileOrder.length) {
    fileTree.innerHTML = `<div class="workspace-picker-empty">${escapeHtml(t("noFilesInWorkspace"))}</div>`;
    return;
  }

  const entries = workspaceEntries.length
    ? workspaceEntries
    : [
        {
          type: "file",
          name: currentFile,
          path: currentFile,
        },
      ];

  fileTree.innerHTML = renderTreeEntries(entries);
  scheduleTreeActionMenuPlacement();
}

let pendingTreeActionMenuPlacementFrame = 0;

function scheduleTreeActionMenuPlacement() {
  if (pendingTreeActionMenuPlacementFrame) {
    cancelAnimationFrame(pendingTreeActionMenuPlacementFrame);
  }

  pendingTreeActionMenuPlacementFrame = requestAnimationFrame(() => {
    pendingTreeActionMenuPlacementFrame = 0;
    positionOpenTreeActionMenu();
  });
}

function positionOpenTreeActionMenu() {
  if (!openFileActionMenu) {
    return;
  }

  const card = fileTree.querySelector(".tree-file-card.is-actions-open");
  const strip = card?.querySelector(".tree-action-strip");
  const panel = fileTree.closest(".drawer-panel");
  if (!card || !strip || !panel) {
    return;
  }

  card.classList.remove("is-actions-upward");

  const stripRect = strip.getBoundingClientRect();
  const panelRect = panel.getBoundingClientRect();
  const spaceBelow = panelRect.bottom - stripRect.top;

  if (spaceBelow < stripRect.height + 12) {
    card.classList.add("is-actions-upward");
  }
}

function closeFileTab(fileName) {
  if (!fileOrder.includes(fileName) || fileOrder.length <= 1) {
    renderEditor();
    return;
  }

  const index = fileOrder.indexOf(fileName);
  fileOrder = fileOrder.filter((entry) => entry !== fileName);

  if (currentFile === fileName) {
    const nextFile = fileOrder[Math.max(0, index - 1)] ?? fileOrder[0];
    focusFile(nextFile);
    return;
  }

  renderEditor();
}

async function deleteWorkspaceFile(fileName) {
  try {
    const response = await fetch(`${workspaceApiBase}/delete-file`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: fileName }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `delete file failed with ${response.status}`);
    }

    pendingDeleteFile = null;
    openFileActionMenu = null;
    workspaceLoadedFiles.delete(fileName);
    delete fileSources[fileName];
    delete fileDirty[fileName];

    const remainingFiles = workspaceFiles.filter((entry) => entry !== fileName);
    const preferredFile =
      currentFile === fileName
        ? chooseWorkspaceFile(undefined, remainingFiles)
        : currentFile;

    await loadWorkspace({ preferredFile, resetState: true });

    if (!workspaceFiles.length) {
      currentFile = primaryFile;
      fileOrder = [primaryFile];
      fileSources[primaryFile] = fileSources[primaryFile] ?? "";
      fileDirty[primaryFile] = false;
    }

    await focusFile(currentFile);
  } catch (error) {
    console.error(error);
    pendingDeleteFile = null;
    openFileActionMenu = null;
    renderEditor();
  }
}

async function deleteWorkspacePaths(paths) {
  const normalizedPaths = normalizeDeleteSelection(paths);
  if (!normalizedPaths.length) {
    return;
  }

  try {
    const response = await fetch(`${workspaceApiBase}/delete-paths`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ paths: normalizedPaths }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `delete paths failed with ${response.status}`);
    }

    normalizedPaths.forEach((entry) => {
      workspaceLoadedFiles.delete(entry);
      delete fileSources[entry];
      delete fileDirty[entry];
    });

    const remainingFiles = workspaceFiles.filter((entry) => !normalizedPaths.includes(entry));
    const preferredFile = normalizedPaths.includes(currentFile)
      ? chooseWorkspaceFile(undefined, remainingFiles)
      : currentFile;
    if (normalizedPaths.some((entry) => activeTreePath === entry || activeTreePath.startsWith(`${entry}/`))) {
      activeTreePath = preferredFile;
    }

    pendingDeleteFile = null;
    openFileActionMenu = null;
    exitBulkDeleteMode();

    await loadWorkspace({ preferredFile, resetState: true });

    if (!workspaceFiles.length) {
      currentFile = primaryFile;
      fileOrder = [primaryFile];
      fileSources[primaryFile] = fileSources[primaryFile] ?? "";
      fileDirty[primaryFile] = false;
    }

    await focusFile(currentFile);
  } catch (error) {
    console.error(error);
    renderEditor();
  }
}

async function confirmDeletePaths(paths) {
  const deleteItems = normalizeDeleteSelection(paths);
  if (!deleteItems.length) {
    return;
  }

  const confirmed = await openConfirmDialog({
    title: "",
    message:
      deleteItems.length === 1
        ? t("deleteSinglePrompt")
        : t("deleteMultiplePrompt", { count: deleteItems.length }),
    confirmLabel: t("delete"),
    destructive: true,
    items: deleteItems,
  });
  if (confirmed === null) {
    return;
  }

  await deleteWorkspacePaths(deleteItems);
}

async function refreshWorkspace(preferredFile = currentFile) {
  openFileActionMenu = null;
  pendingDeleteFile = null;
  exitBulkDeleteMode();
  activeTreePath = "";
  await loadWorkspace({ preferredFile, resetState: true });
  editorInput.value = fileSources[currentFile] ?? "";
  renderEditor();
}

async function renameWorkspaceFile(fileName) {
  const displayedPath = formatWorkspaceDraftPath(fileName);
  const suggestedPath = await openPromptDialog({
    title: t("renameFile"),
    message: t("renameFileMessage"),
    confirmLabel: t("rename"),
    input: displayedPath,
    placeholder: displayedPath,
  });
  if (suggestedPath === null) {
    return;
  }

  const nextPath = normalizeWorkspaceDraftPath(suggestedPath);
  if (!nextPath || nextPath === fileName) {
    return;
  }

  try {
    const response = await fetch(`${workspaceApiBase}/rename-file`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: fileName, nextPath }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `rename file failed with ${response.status}`);
    }

    const nextFile = payload.nextFile ?? nextPath;
    const existingSource = fileSources[fileName];
    const existingDirty = fileDirty[fileName];
    if (typeof existingSource === "string") {
      fileSources[nextFile] = existingSource;
    }
    if (typeof existingDirty === "boolean") {
      fileDirty[nextFile] = existingDirty;
    }
    delete fileSources[fileName];
    delete fileDirty[fileName];
    workspaceLoadedFiles.delete(fileName);
    workspaceLoadedFiles.add(nextFile);

    fileOrder = fileOrder.map((entry) => (entry === fileName ? nextFile : entry));
    if (currentFile === fileName) {
      currentFile = nextFile;
    }
    if (activeTreePath === fileName) {
      activeTreePath = nextFile;
    }

    openFileActionMenu = null;
    pendingDeleteFile = null;
    await loadWorkspace({ preferredFile: currentFile });
    await focusFile(currentFile);
  } catch (error) {
    console.error(error);
  }
}

async function createWorkspaceEntry(kind) {
  const isFile = kind === "file";
  const defaultTarget = defaultCreateTarget(kind);
  const relativePath = await openPromptDialog({
    title: isFile ? t("createFileTitle") : t("createFolderTitle"),
    message: isFile ? t("createFileMessage") : t("createFolderMessage"),
    confirmLabel: activeLanguageKey === "zhCn" ? "创建" : "Create",
    input: defaultTarget,
    placeholder: defaultTarget,
  });
  if (relativePath === null) {
    return;
  }

  const nextPath = normalizeWorkspaceDraftPath(relativePath);
  if (!nextPath) {
    return;
  }

  try {
    const response = await fetch(`${workspaceApiBase}/${isFile ? "create-file" : "create-folder"}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(isFile ? { path: nextPath, content: "" } : { path: nextPath }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `create ${kind} failed with ${response.status}`);
    }

    if (isFile) {
      await loadWorkspace({ preferredFile: payload.file });
      await focusFile(payload.file);
      return;
    }

    await refreshWorkspace(currentFile);
  } catch (error) {
    console.error(error);
  }
}

async function createWorkspaceFile() {
  await createWorkspaceEntry("file");
}

async function createWorkspaceFolder() {
  await createWorkspaceEntry("folder");
}

async function loadWorkspaceFile(fileName) {
  if (!workspaceApiAvailable || !fileName) {
    return fileSources[fileName] ?? fallbackSources[fileName] ?? "";
  }

  if (workspaceLoadedFiles.has(fileName) && typeof fileSources[fileName] === "string") {
    return fileSources[fileName];
  }

  const response = await fetch(`${workspaceApiBase}/file/${encodeURIComponent(fileName)}`, {
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error(`file load failed with ${response.status}`);
  }

  const payload = await response.json();
  fileSources[fileName] = payload.content ?? "";
  fileDirty[fileName] = false;
  workspaceLoadedFiles.add(fileName);
  return fileSources[fileName];
}

function renderWorkspacePicker(snapshot) {
  workspacePickerPath = snapshot.currentPath || "";
  workspacePickerParentPath = snapshot.parentPath || null;
  workspacePickerSelectedFilePath = snapshot.selectedFilePath || "";
  workspacePickerCurrent.value =
    workspacePickerMode === "file" && workspacePickerSelectedFilePath
      ? workspacePickerSelectedFilePath
      : workspacePickerPath;
  workspacePickerUp.disabled = !workspacePickerParentPath;
  workspacePickerConfirm.disabled =
    workspacePickerMode === "file" ? !workspacePickerSelectedFilePath : false;

  workspacePickerBreadcrumbs.innerHTML = (snapshot.breadcrumbs || [])
    .map(
      (crumb) => `
        <button class="workspace-picker-breadcrumb" type="button" data-picker-path="${escapeHtml(crumb.path)}">
          ${escapeHtml(crumb.name)}
        </button>
      `,
    )
    .join("");

  const directoryMarkup = (snapshot.directories || [])
    .map(
      (directory) => `
        <button class="workspace-picker-entry" type="button" data-picker-path="${escapeHtml(directory.path)}" data-picker-kind="directory">
          <span class="workspace-picker-entry-icon" aria-hidden="true">
            <svg viewBox="0 0 24 24">
              <path d="M3.75 7.75A1.75 1.75 0 0 1 5.5 6h4.05c.4 0 .79.16 1.07.44l1.24 1.24c.28.28.66.44 1.06.44h5.58a1.75 1.75 0 0 1 1.75 1.75v6.38A1.75 1.75 0 0 1 18.5 18H5.5a1.75 1.75 0 0 1-1.75-1.75z"></path>
              <path d="M3.75 10h16.5"></path>
            </svg>
          </span>
          <span class="workspace-picker-entry-copy">
            <span class="workspace-picker-entry-name">${escapeHtml(directory.name)}</span>
            <span class="workspace-picker-entry-path">${escapeHtml(directory.path)}</span>
          </span>
          <span class="workspace-picker-entry-chevron" aria-hidden="true"></span>
        </button>
      `,
    )
    .join("");

  const fileMarkup = workspacePickerIncludeFiles
    ? (snapshot.files || [])
        .map(
          (file) => `
            <button class="workspace-picker-entry workspace-picker-entry-file ${workspacePickerSelectedFilePath === file.path ? "is-selected" : ""}" type="button" data-picker-path="${escapeHtml(file.path)}" data-picker-kind="file">
              <span class="workspace-picker-entry-icon" aria-hidden="true">
                <svg viewBox="0 0 24 24">
                  <path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z"></path>
                  <path d="M14 2v5a1 1 0 0 0 1 1h5"></path>
                </svg>
              </span>
              <span class="workspace-picker-entry-copy">
                <span class="workspace-picker-entry-name">${escapeHtml(file.name)}</span>
                <span class="workspace-picker-entry-path">${escapeHtml(file.path)}</span>
              </span>
            </button>
          `,
        )
        .join("")
    : "";

  const markup = `${directoryMarkup}${fileMarkup}`;
  workspacePickerList.innerHTML = markup
    ? markup
    : `<div class="workspace-picker-empty">${escapeHtml(
        workspacePickerIncludeFiles ? t("noFilesFound") : t("noDirectoriesFound"),
      )}</div>`;
}

function syncWorkspacePickerSelection() {
  workspacePickerList
    .querySelectorAll('[data-picker-kind="file"]')
    .forEach((button) => {
      button.classList.toggle("is-selected", button.dataset.pickerPath === workspacePickerSelectedFilePath);
    });
}

async function browseWorkspaceEntries(path) {
  const targetPath = (path || workspaceRootPath || "").trim();
  if (!targetPath) {
    return false;
  }

  workspacePickerCurrent.value = targetPath;
  workspacePickerList.innerHTML = `<div class="workspace-picker-empty">${escapeHtml(t("loadingFolders"))}</div>`;
  setWorkspacePickerMessage(workspacePickerDefaultCaptionText || t("chooseWorkspaceRoot"));

  try {
    const response = await fetch(
      `/api/browser/entries?path=${encodeURIComponent(targetPath)}&includeFiles=${workspacePickerIncludeFiles ? "1" : "0"}`,
      {
        cache: "no-store",
      },
    );

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `directory browse failed with ${response.status}`);
    }

    renderWorkspacePicker(payload);
    return true;
  } catch (error) {
    console.error(error);
    workspacePickerSelectedFilePath = "";
    workspacePickerConfirm.disabled = workspacePickerMode === "file";
    workspacePickerList.innerHTML = `<div class="workspace-picker-empty">${escapeHtml(error.message)}</div>`;
    setWorkspacePickerMessage(error.message);
    return false;
  }
}

function openWorkspacePicker(startPath = workspaceRootPath) {
  setWorkspacePickerState({
    mode: "directory",
    includeFiles: false,
    title: t("openWorkspaceTitle"),
    caption: t("chooseWorkspaceRoot"),
    confirmLabel: t("useThisFolder"),
    onConfirm: async (selectedPath) => {
      await applyWorkspaceRoot(selectedPath);
    },
  });
  workspacePickerOverlay.hidden = false;
  browseWorkspaceEntries(startPath);
}

function closeWorkspacePicker() {
  workspacePickerOverlay.hidden = true;
  workspacePickerSelectedFilePath = "";
  workspacePickerConfirmAction = null;
  setWorkspacePickerMessage(t("chooseWorkspaceRoot"));
}

async function applyWorkspaceRoot(path) {
  const nextPath = (path || "").trim();
  if (!nextPath) {
    setWorkspacePickerMessage(t("chooseWorkspaceRoot"));
    return;
  }

  workspacePickerConfirm.disabled = true;

  try {
    const response = await fetch(`${workspaceApiBase}/root`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ path: nextPath }),
    });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || `workspace change failed with ${response.status}`);
    }

    workspaceRootPath = payload.rootPath ?? nextPath;
    closeWorkspacePicker();
    await loadWorkspace({ preferredFile: primaryFile, resetState: true });
    renderEditor();
  } catch (error) {
    console.error(error);
    setWorkspacePickerMessage(error.message);
  } finally {
    workspacePickerConfirm.disabled = false;
  }
}

async function readBrowserTextFile(path) {
  const response = await fetch(`/api/browser/file?path=${encodeURIComponent(path)}`, {
    cache: "no-store",
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || `file read failed with ${response.status}`);
  }
  return payload;
}

function applyImportedPaletteConfig(rawText) {
  const parsedConfig = parseCustomPaletteConfig(rawText);
  applyCustomPaletteConfig(parsedConfig);
  persistLanguageState();
  persistThemeSettings();
  persistEditorSurfaceState();
  document.body.classList.toggle("glyphs-off", !glyphsOn);
  updateIndentUi();
  toggleGlyphs.setAttribute("aria-pressed", String(glyphsOn));
  toggleGlyphs.setAttribute("aria-label", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
  toggleGlyphs.setAttribute("title", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
  flushFullAppRender();
}

async function openPaletteConfigImportPicker(startPath = workspaceRootPath) {
  setWorkspacePickerState({
    mode: "file",
    includeFiles: true,
    title: t("importConfigFile"),
    caption: t("chooseConfigFile"),
    confirmLabel: t("importThisFile"),
    onConfirm: async (selectedPath) => {
      const payload = await readBrowserTextFile(selectedPath);
      applyImportedPaletteConfig(payload.content ?? "");
      closeWorkspacePicker();
      showAppToast(t("configImported"), "success");
    },
  });
  workspacePickerOverlay.hidden = false;
  await browseWorkspaceEntries(startPath);
}

async function openPaletteConfigEditor() {
  const rawText = await openTextareaDialog({
    title: t("themeConfig"),
    message: t("themeConfigMessage"),
    confirmLabel: t("confirm"),
    cancelLabel: t("cancel"),
    textarea: buildCustomPaletteConfigText(),
    placeholder: "{\n  \"$schema\": \"https://styio.dev/schemas/theme-customizations.json\"\n}",
  });
  if (rawText === null) {
    return;
  }

  try {
    applyImportedPaletteConfig(rawText);
    showAppToast(t("configSaved"), "success");
  } catch (error) {
    console.error(error);
    await openConfirmDialog({
      title: "",
      message: error.message,
      confirmLabel: t("confirm"),
    });
  }
}

function renderGutter(analysis) {
  const issueLines = new Set([
    ...analysis.warnings.map((entry) => entry.lineIndex),
    ...analysis.errors.map((entry) => entry.lineIndex),
  ]);
  const lineDigits = String(Math.max(analysis.lines.length, 1)).length;
  const gutterWidth = 52 + Math.max(0, lineDigits - 3) * 10;
  document.documentElement.style.setProperty("--editor-gutter-width", `${gutterWidth}px`);

  lineGutter.innerHTML = analysis.lines
    .map((_, index) => {
      const classes = ["gutter-line"];
      if (issueLines.has(index)) {
        classes.push("has-issue");
      }
      return `<span class="${classes.join(" ")}">${padLine(index)}</span>`;
    })
    .join("");
}

function renderLines(analysis) {
  const issueLines = new Set([
    ...analysis.warnings.map((entry) => entry.lineIndex),
    ...analysis.errors.map((entry) => entry.lineIndex),
  ]);
  const { start: selectionStart, end: selectionEnd } = normalizedSelectionRange();
  const caretLine = selectionStart === selectionEnd ? getCaretLineIndex() : -1;

  renderLayer.innerHTML = analysis.lines
    .map((line, index) => {
      const classes = ["editor-line"];
      if (index === caretLine) {
        classes.push("is-selected");
      }
      if (issueLines.has(index)) {
        classes.push("has-issue");
      }

      return `<div class="${classes.join(" ")}" data-line="${index}"><span class="code-text">${renderLineWithSelection(
        line,
        analysis.lineStarts[index],
        editorInput.selectionStart,
        selectionStart,
        selectionEnd,
      )}</span></div>`;
    })
    .join("");
}

function syncOverlayMetrics() {
  const width = Math.max(editorInput.scrollWidth, codeStage.clientWidth);
  const height = Math.max(editorInput.scrollHeight, codeStage.clientHeight);
  renderLayer.style.width = `${width}px`;
  renderLayer.style.height = `${height}px`;
  blockLayer.style.width = `${width}px`;
  blockLayer.style.height = `${height}px`;
}

function renderBlocks(analysis) {
  const highlights = [];

  analysis.blocks.forEach((block) => {
    const startNode = renderLayer.querySelector(`[data-line="${block.visualStart}"]`);
    const endNode = renderLayer.querySelector(`[data-line="${block.closing}"]`);
    if (!startNode || !endNode) {
      return;
    }

    const top = startNode.offsetTop - 4;
    const bottom = endNode.offsetTop + endNode.offsetHeight + 4;
    highlights.push(
      `<div class="block-highlight block-${block.type}" title="${escapeHtml(block.type)} ${escapeHtml(block.title)}" style="top:${top}px;height:${Math.max(32, bottom - top)}px;"></div>`,
    );
  });

  blockLayer.innerHTML = highlights.join("");
}

function syncScroll() {
  renderLayer.style.transform = `translate(${-editorInput.scrollLeft}px, ${-editorInput.scrollTop}px)`;
  blockLayer.style.transform = `translate(${-editorInput.scrollLeft}px, ${-editorInput.scrollTop}px)`;
  caretLayer.style.transform = `translate(${-editorInput.scrollLeft}px, ${-editorInput.scrollTop}px)`;
  lineGutter.style.transform = `translateY(${-editorInput.scrollTop}px)`;
}

function syncCaretIndicator(analysis) {
  if (hasSelection()) {
    caretIndicator.style.opacity = "0";
    return;
  }

  caretIndicator.style.opacity = "1";
  const rawOffset = editorInput.selectionStart;
  const lineIndex = lineIndexForOffset(analysis, rawOffset);

  const lineStart = analysis.lineStarts[lineIndex];
  const lineText = analysis.lines[lineIndex];
  const { x } = getCaretCoordinates(lineText, lineStart, rawOffset);
  const padY = getCssNumber("--editor-pad-y");
  const padX = getCssNumber("--editor-pad-x");
  const lineHeight = getCssNumber("--editor-line-height");

  caretIndicator.style.top = `${padY + lineIndex * lineHeight + 2}px`;
  caretIndicator.style.left = `${padX + x}px`;
}

function setSaveState(kind, text) {
  if (!saveState) {
    return;
  }
  saveState.dataset.saveState = kind;
  saveState.textContent = text;
}

function updateIndentUi() {
  document.querySelectorAll("[data-indent-size]").forEach((button) => {
    const active = Number(button.dataset.indentSize) === indentSize;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-pressed", String(active));
  });
  if (indentState) {
    indentState.textContent =
      activeLanguageKey === "zhCn" ? `缩进：${indentSize} 个空格` : `indent: ${indentSize} spaces`;
  }
}

function updateStatusbar(analysis) {
  latestAnalysis = analysis;
  syncStyleShellTitles(styleShellBridge, {
    appTitle: t("appTitle"),
    workspaceTitle: t("workspace"),
  });
  workspacePathHint.hidden = true;
  workspacePathHint.textContent = "";
  if (glyphState) {
    glyphState.textContent =
      activeLanguageKey === "zhCn"
        ? `符号：${glyphsOn ? "开启" : "关闭"} / ${analysis.glyphCount}`
        : `glyphs: ${glyphsOn ? "on" : "off"} / ${analysis.glyphCount}`;
  }
  updateIndentUi();
  if (unitState) {
    unitState.textContent = analysis.ready
      ? activeLanguageKey === "zhCn"
        ? "单元：就绪"
        : "unit: ready"
      : activeLanguageKey === "zhCn"
        ? "单元：未完成"
        : "unit: incomplete";
  }
  if (issueState) {
    issueState.textContent =
      activeLanguageKey === "zhCn"
        ? `诊断：${analysis.warnings.length} 个警告 / ${analysis.errors.length} 个错误`
        : `diagnostics: ${analysis.warnings.length} warning / ${analysis.errors.length} errors`;
  }
  if (renderState) {
    renderState.textContent =
      activeLanguageKey === "zhCn"
        ? `投影：${analysis.glyphCount} 个符号 / ${analysis.blocks.length} 个块`
        : `projection: ${analysis.glyphCount} glyphs / ${analysis.blocks.length} blocks`;
  }
  const { start, end } = normalizedSelectionRange();
  if (start === end) {
    if (cursorState) {
      cursorState.textContent =
        activeLanguageKey === "zhCn"
          ? `选区：第 ${padLine(lineIndexForOffset(analysis, start))} 行`
          : `selection: line ${padLine(lineIndexForOffset(analysis, start))}`;
    }
    return;
  }

  const startLine = lineIndexForOffset(analysis, start);
  const endLine = lineIndexForOffset(analysis, Math.max(start, end - 1));
  if (cursorState) {
    cursorState.textContent =
      activeLanguageKey === "zhCn"
        ? `选区：${padLine(startLine)}-${padLine(endLine)} / ${end - start} 个字符`
        : `selection: ${padLine(startLine)}-${padLine(endLine)} / ${end - start} chars`;
  }
}

function updateSaveUi() {
  if (saveFile) {
    saveFile.disabled = saveInFlight;
    saveFile.textContent = saveInFlight ? (activeLanguageKey === "zhCn" ? "保存中..." : "Saving...") : activeLanguageKey === "zhCn" ? "保存" : "Save";
  }

  if (!workspaceApiAvailable) {
    setSaveState("volatile", activeLanguageKey === "zhCn" ? "磁盘：接口离线" : "disk: api offline");
    return;
  }

  if (saveInFlight) {
    setSaveState("saving", activeLanguageKey === "zhCn" ? "磁盘：保存中" : "disk: saving");
    return;
  }

  if (fileDirty[currentFile]) {
    setSaveState("dirty", activeLanguageKey === "zhCn" ? "磁盘：有未保存改动" : "disk: unsaved edits");
    return;
  }

  setSaveState("saved", activeLanguageKey === "zhCn" ? `磁盘：已保存 / ${currentFile}` : `disk: saved / ${currentFile}`);
}

function renderEditor() {
  flushRender(renderGroups.fullEditor);
}

async function focusFile(fileName) {
  if (!fileName) {
    return;
  }

  if (!fileOrder.includes(fileName)) {
    fileOrder.push(fileName);
  }

  currentFile = fileName;
  activeTreePath = fileName;
  try {
    await loadWorkspaceFile(fileName);
  } catch (error) {
    console.error(error);
    if (typeof fileSources[fileName] !== "string") {
      fileSources[fileName] = "";
      fileDirty[fileName] = false;
    }
  }
  editorInput.value = fileSources[currentFile];
  editorInput.scrollTop = 0;
  editorInput.scrollLeft = 0;
  renderEditor();
}

function replaceSelection(replacement, nextSelectionStart, nextSelectionEnd = nextSelectionStart) {
  const start = editorInput.selectionStart;
  const end = editorInput.selectionEnd;
  const nextValue = `${editorInput.value.slice(0, start)}${replacement}${editorInput.value.slice(end)}`;
  editorInput.value = nextValue;
  editorInput.setSelectionRange(nextSelectionStart, nextSelectionEnd);
  fileSources[currentFile] = nextValue;
  fileDirty[currentFile] = true;
  requestSidebarRender();
  requestEditorContentRender();
}

function currentLineStart(value, offset) {
  return value.lastIndexOf("\n", Math.max(0, offset - 1)) + 1;
}

function currentLineEnd(value, offset) {
  const newlineIndex = value.indexOf("\n", offset);
  return newlineIndex === -1 ? value.length : newlineIndex;
}

function leadingSpaces(value, offset) {
  const lineStart = currentLineStart(value, offset);
  const lineEnd = currentLineEnd(value, offset);
  const line = value.slice(lineStart, lineEnd);
  return line.match(/^ */)?.[0] ?? "";
}

function handleIndent() {
  const start = editorInput.selectionStart;
  const end = editorInput.selectionEnd;
  const value = editorInput.value;
  const unit = indentUnit();

  if (start === end) {
    replaceSelection(unit, start + unit.length);
    return;
  }

  const lineStart = value.lastIndexOf("\n", start - 1) + 1;
  const selectionText = value.slice(lineStart, end);
  const indented = selectionText
    .split("\n")
    .map((line) => `${unit}${line}`)
    .join("\n");
  replaceSelection(
    indented,
    start + unit.length,
    end + unit.length * selectionText.split("\n").length,
  );
}

function handleOutdent() {
  const start = editorInput.selectionStart;
  const end = editorInput.selectionEnd;
  const value = editorInput.value;
  const unit = indentUnit();

  if (start === end) {
    const lineStart = currentLineStart(value, start);
    const lineEnd = currentLineEnd(value, start);
    const line = value.slice(lineStart, lineEnd);
    const removable = line.startsWith(unit)
      ? unit.length
      : line.startsWith(" ")
        ? Math.min(indentSize, line.match(/^ +/)?.[0]?.length ?? 0)
        : 0;
    if (removable === 0) {
      return;
    }
    editorInput.selectionStart = lineStart;
    editorInput.selectionEnd = lineStart + removable;
    const nextOffset = Math.max(lineStart, start - removable);
    replaceSelection("", nextOffset);
    return;
  }

  const lineStart = value.lastIndexOf("\n", start - 1) + 1;
  const selectionText = value.slice(lineStart, end);
  const lines = selectionText.split("\n");
  let removedBeforeStart = 0;
  let removedTotal = 0;

  const outdented = lines
    .map((line, index) => {
      const removable = line.startsWith(unit)
        ? unit.length
        : line.startsWith(" ")
          ? Math.min(indentSize, line.match(/^ +/)[0].length)
          : 0;
      if (index === 0) {
        removedBeforeStart = Math.min(removable, start - lineStart);
      }
      removedTotal += removable;
      return line.slice(removable);
    })
    .join("\n");

  const nextStart = Math.max(lineStart, start - removedBeforeStart);
  const nextEnd = Math.max(nextStart, end - removedTotal);
  editorInput.selectionStart = lineStart;
  editorInput.selectionEnd = end;
  replaceSelection(outdented, nextStart, nextEnd);
}

function handleNewlineIndent() {
  const start = editorInput.selectionStart;
  const value = editorInput.value;
  const inheritedIndent = leadingSpaces(value, start);
  replaceSelection(`\n${inheritedIndent}`, start + 1 + inheritedIndent.length);
}

function handleBackspaceIndent() {
  const start = editorInput.selectionStart;
  const end = editorInput.selectionEnd;
  if (start !== end || start === 0) {
    return false;
  }

  const value = editorInput.value;
  const lineStart = currentLineStart(value, start);
  const linePrefix = value.slice(lineStart, start);
  if (!/^ +$/.test(linePrefix)) {
    return false;
  }

  const removeCount = Math.min(indentSize, linePrefix.length);
  if (removeCount <= 0) {
    return false;
  }

  editorInput.selectionStart = start - removeCount;
  editorInput.selectionEnd = start;
  replaceSelection("", start - removeCount);
  return true;
}

async function loadWorkspace(options = {}) {
  const { preferredFile = currentFile, resetState = false } = options;
  try {
    const response = await fetch(workspaceApiBase, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`workspace load failed with ${response.status}`);
    }

    const payload = await response.json();
    workspaceRootPath = payload.rootPath || "";
    workspaceName = payload.workspaceName || "workspace";
    workspaceEntries = Array.isArray(payload.entries) ? payload.entries : [];
    workspaceFiles = Array.isArray(payload.files) && payload.files.length ? payload.files : [primaryFile];
    const availableDirectoryPaths = collectDirectoryPaths(workspaceEntries);

    if (resetState) {
      workspaceLoadedFiles = new Set();
      Object.keys(fileDirty).forEach((fileName) => {
        delete fileDirty[fileName];
      });
    }

    workspaceFiles.forEach((fileName) => {
      if (!(fileName in fileDirty)) {
        fileDirty[fileName] = false;
      }
    });

    const availableTreePaths = collectTreePaths(workspaceEntries, new Set(workspaceFiles));
    if (!expandedTreePaths.size && availableDirectoryPaths.size) {
      expandedTreePaths = new Set(availableDirectoryPaths);
    } else {
      expandedTreePaths = new Set(Array.from(expandedTreePaths).filter((entry) => availableDirectoryPaths.has(entry)));
    }
    selectedTreePaths = new Set(Array.from(selectedTreePaths).filter((entry) => availableTreePaths.has(entry)));
    if (activeTreePath && !availableTreePaths.has(activeTreePath)) {
      activeTreePath = chooseWorkspaceFile(preferredFile, workspaceFiles);
    }

    const nextCurrentFile = chooseWorkspaceFile(preferredFile, workspaceFiles);
    const nextTabs = fileOrder.filter((fileName) => workspaceFiles.includes(fileName));
    if (!nextTabs.includes(nextCurrentFile)) {
      nextTabs.push(nextCurrentFile);
    }

    fileOrder = nextTabs.length ? nextTabs : [nextCurrentFile];
    currentFile = nextCurrentFile;
    await loadWorkspaceFile(currentFile);

    workspaceApiAvailable = true;
    syncWorkspaceControls();
  } catch (error) {
    console.error(error);
    workspaceApiAvailable = false;
    workspaceRootPath = "";
    workspaceName = "workspace";
    workspaceEntries = [];
    workspaceFiles = [primaryFile];
    fileOrder = [primaryFile];
    currentFile = primaryFile;
    [primaryFile].forEach((fileName) => {
      if (!(fileName in fileDirty)) {
        fileDirty[fileName] = false;
      }
    });
    syncWorkspaceControls();
  }
}

async function saveCurrentFile() {
  if (saveInFlight) {
    return;
  }

  clearAutoSaveTimer();

  if (!workspaceApiAvailable) {
    setSaveState("volatile", "disk: api offline");
    return;
  }

  saveInFlight = true;
  updateSaveUi();

  try {
    const response = await fetch(`${workspaceApiBase}/file/${encodeURIComponent(currentFile)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: editorInput.value }),
    });

    if (!response.ok) {
      throw new Error(`save failed with ${response.status}`);
    }

    await response.json();
    fileSources[currentFile] = editorInput.value;
    fileDirty[currentFile] = false;
    workspaceLoadedFiles.add(currentFile);
    requestSidebarRender();
    requestRender(RenderSlice.saveUi);
  } catch (error) {
    console.error(error);
    setSaveState("error", "disk: save failed");
  } finally {
    saveInFlight = false;
    updateSaveUi();
  }
}

appDialogClose.addEventListener("click", () => {
  closeAppDialog(null);
});

appDialogCancel.addEventListener("click", () => {
  closeAppDialog(null);
});

appDialogConfirm.addEventListener("click", () => {
  if (!appDialogTextareaField.hidden) {
    closeAppDialog(appDialogTextarea.value);
    return;
  }
  closeAppDialog(appDialogInputField.hidden ? true : appDialogInput.value);
});

appDialogOverlay.addEventListener("click", (event) => {
  if (event.target === appDialogOverlay) {
    closeAppDialog(null);
  }
});

appDialogInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    closeAppDialog(appDialogInput.value);
    return;
  }

  if (event.key === "Escape") {
    event.preventDefault();
    closeAppDialog(null);
  }
});

appDialogTextarea.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "enter") {
    event.preventDefault();
    closeAppDialog(appDialogTextarea.value);
    return;
  }

  if (event.key === "Escape") {
    event.preventDefault();
    closeAppDialog(null);
  }
});

document.addEventListener("keydown", (event) => {
  if (appDialogOverlay.hidden) {
    return;
  }

  if (event.key === "Escape") {
    event.preventDefault();
    closeAppDialog(null);
    return;
  }

  if (event.key === "Enter" && appDialogInputField.hidden && appDialogTextareaField.hidden) {
    event.preventDefault();
    closeAppDialog(true);
  }
});

bindStyleShellBridgeEvents(styleShellBridge, {
  onGridToggle: () => {
    sidebarOpen = !sidebarOpen;
    syncSidebar();
  },
  onGridClose: () => {
    sidebarOpen = false;
    syncSidebar();
  },
  onEditorialToggle: () => {
    sidebarOpen = !sidebarOpen;
    syncSidebar();
  },
  onEditorialFiles: () => {
    activeDrawerTab = "files";
    sidebarOpen = true;
    syncSidebar();
  },
  onEditorialSettings: () => {
    activeDrawerTab = "settings";
    sidebarOpen = true;
    syncSidebar();
  },
});

drawerTabs.forEach((button) => {
  button.addEventListener("click", () => {
    activeDrawerTab = button.dataset.drawerTab;
    sidebarOpen = true;
    syncSidebar();
  });
});

fileTabs.addEventListener("click", (event) => {
  const closeButton = event.target.closest("[data-tab-close]");
  if (closeButton) {
    event.preventDefault();
    event.stopPropagation();
    openFileActionMenu = null;
    pendingDeleteFile = null;
    closeFileTab(closeButton.dataset.tabClose);
    return;
  }

  const tabButton = event.target.closest("[data-tab-file]");
  if (!tabButton) {
    return;
  }

  openFileActionMenu = null;
  pendingDeleteFile = null;
  focusFile(tabButton.dataset.tabFile);
});

fileTree.addEventListener("click", (event) => {
  const selectToggle = event.target.closest("[data-select-tree-path]");
  if (selectToggle) {
    event.preventDefault();
    event.stopPropagation();
    const treePath = selectToggle.dataset.selectTreePath;
    if (selectedTreePaths.has(treePath)) {
      selectedTreePaths.delete(treePath);
    } else {
      selectedTreePaths.add(treePath);
    }
    requestSidebarRender();
    return;
  }

  const folderSummary = event.target.closest("[data-tree-folder]");
  if (folderSummary) {
    event.preventDefault();
    const folderPath = folderSummary.dataset.treeFolder;
    if (expandedTreePaths.has(folderPath)) {
      expandedTreePaths.delete(folderPath);
    } else {
      expandedTreePaths.add(folderPath);
    }
    if (bulkDeleteMode) {
      activeTreePath = folderPath;
      if (selectedTreePaths.has(folderPath)) {
        selectedTreePaths.delete(folderPath);
      } else {
        selectedTreePaths.add(folderPath);
      }
    } else {
      activeTreePath = folderPath;
    }
    requestSidebarRender();
    return;
  }

  const previewButton = event.target.closest("[data-preview-file]");
  if (previewButton) {
    event.preventDefault();
    event.stopPropagation();
    focusFile(previewButton.dataset.previewFile);
    return;
  }

  const fileButton = event.target.closest("[data-tree-file]");
  if (!fileButton) {
    return;
  }

  if (bulkDeleteMode) {
    event.preventDefault();
    const fileName = fileButton.dataset.treeFile;
    activeTreePath = fileName;
    if (selectedTreePaths.has(fileName)) {
      selectedTreePaths.delete(fileName);
    } else {
      selectedTreePaths.add(fileName);
    }
    requestSidebarRender();
    return;
  }

  pendingDeleteFile = null;
  openFileActionMenu = null;
  const fileName = fileButton.dataset.treeFile;
  if (activeTreePath === fileName) {
    activeTreePath = "";
    requestSidebarRender();
    return;
  }

  focusFile(fileName);
  activeDrawerTab = "files";
  syncSidebar();
});

workspacePathApply.addEventListener("click", () => {
  openWorkspacePicker(workspaceRootPath);
});

workspaceCalloutOpen.addEventListener("click", () => {
  openWorkspacePicker(workspaceRootPath);
});

workspacePathViewport?.addEventListener("scroll", () => {
  syncWorkspacePathVisual();
});

workspacePathScrollVisual?.addEventListener("pointerdown", (event) => {
  if (!workspacePathViewport || !workspacePathScrollVisual || !workspacePathScrollThumb || !workspacePathText) {
    return;
  }

  const trackRect = workspacePathScrollVisual.getBoundingClientRect();
  const thumbRect = workspacePathScrollThumb.getBoundingClientRect();
  const viewportWidth = workspacePathViewport.clientWidth;
  const contentWidth = workspacePathText.scrollWidth;
  const maxScroll = Math.max(0, contentWidth - viewportWidth);

  if (maxScroll <= 0) {
    return;
  }

  const thumbWidth = thumbRect.width;
  const maxThumbTravel = Math.max(0, trackRect.width - thumbWidth);
  const clickedThumb = event.target === workspacePathScrollThumb;
  const offsetX = clickedThumb ? event.clientX - thumbRect.left : thumbWidth / 2;
  workspacePathDrag = { offsetX, maxScroll, maxThumbTravel, trackLeft: trackRect.left };

  const nextThumbX = Math.min(Math.max(event.clientX - trackRect.left - offsetX, 0), maxThumbTravel);
  workspacePathViewport.scrollLeft = maxThumbTravel > 0 ? (nextThumbX / maxThumbTravel) * maxScroll : 0;
  syncWorkspacePathVisual();
});

window.addEventListener("pointermove", (event) => {
  if (!workspacePathDrag || !workspacePathViewport) {
    return;
  }

  const nextThumbX = Math.min(
    Math.max(event.clientX - workspacePathDrag.trackLeft - workspacePathDrag.offsetX, 0),
    workspacePathDrag.maxThumbTravel,
  );
  workspacePathViewport.scrollLeft =
    workspacePathDrag.maxThumbTravel > 0 ? (nextThumbX / workspacePathDrag.maxThumbTravel) * workspacePathDrag.maxScroll : 0;
  syncWorkspacePathVisual();
});

window.addEventListener("pointerup", () => {
  workspacePathDrag = null;
});

window.addEventListener("resize", () => {
  syncWorkspacePathScrollerMetrics();
  scheduleLayoutRender();
});

workspaceShell.addEventListener("transitionend", (event) => {
  if (event.target !== workspaceShell) {
    return;
  }
  if (event.propertyName === "grid-template-columns" || event.propertyName === "gap") {
    scheduleNativeRender();
  }
});

if (window.ResizeObserver) {
  const codeStageResizeObserver = new ResizeObserver(() => {
    scheduleNativeRender();
  });
  codeStageResizeObserver.observe(codeStage);
}

workspacePickerClose.addEventListener("click", () => {
  closeWorkspacePicker();
});

workspacePickerOverlay.addEventListener("click", (event) => {
  if (event.target === workspacePickerOverlay) {
    closeWorkspacePicker();
  }
});

workspacePickerUp.addEventListener("click", () => {
  if (!workspacePickerParentPath) {
    return;
  }
  browseWorkspaceEntries(workspacePickerParentPath);
});

workspacePickerBreadcrumbs.addEventListener("click", (event) => {
  const button = event.target.closest("[data-picker-path]");
  if (!button) {
    return;
  }
  browseWorkspaceEntries(button.dataset.pickerPath);
});

workspacePickerList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-picker-path]");
  if (!button) {
    return;
  }
  const targetPath = button.dataset.pickerPath;
  const kind = button.dataset.pickerKind || "directory";
  if (kind === "file") {
    workspacePickerSelectedFilePath = targetPath;
    workspacePickerCurrent.value = targetPath;
    workspacePickerConfirm.disabled = false;
    syncWorkspacePickerSelection();
    return;
  }
  browseWorkspaceEntries(targetPath);
});

workspacePickerCurrent.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    browseWorkspaceEntries(workspacePickerCurrent.value);
  }
});

workspacePickerCurrent.addEventListener("blur", () => {
  if (!workspacePickerOverlay.hidden && workspacePickerCurrent.value.trim()) {
    browseWorkspaceEntries(workspacePickerCurrent.value);
  }
});

workspacePickerConfirm.addEventListener("click", async () => {
  const targetPath =
    workspacePickerMode === "file"
      ? workspacePickerSelectedFilePath || workspacePickerCurrent.value
      : workspacePickerCurrent.value || workspacePickerPath;
  if (!targetPath) {
    return;
  }

  if (workspacePickerConfirmAction) {
    try {
      await workspacePickerConfirmAction(targetPath);
    } catch (error) {
      console.error(error);
      setWorkspacePickerMessage(error.message);
    }
    return;
  }

  await applyWorkspaceRoot(targetPath);
});

createFolderButton.addEventListener("click", () => {
  createWorkspaceFolder();
});

quickCreateFileButton.addEventListener("click", () => {
  createWorkspaceFile();
});

refreshWorkspaceButton.addEventListener("click", () => {
  if (bulkDeleteMode) {
    exitBulkDeleteMode();
    requestSidebarRender();
    return;
  }

  refreshWorkspace(currentFile);
});

bulkDeleteButton.addEventListener("click", async () => {
  if (!bulkDeleteMode) {
    const activeEntry = activeTreeEntry();
    if (activeEntry) {
      await confirmDeletePaths([activeEntry.path]);
      return;
    }

    bulkDeleteMode = true;
    pendingDeleteFile = null;
    openFileActionMenu = null;
    clearBulkDeleteSelection();
    if (activeTreePath) {
      selectedTreePaths.add(activeTreePath);
    }
    requestSidebarRender();
    return;
  }

  if (!selectedTreePaths.size) {
    exitBulkDeleteMode();
    requestSidebarRender();
    return;
  }

  await confirmDeletePaths(Array.from(selectedTreePaths));
});

workspaceMoreButton.addEventListener("click", () => {
  openWorkspacePicker(workspaceRootPath);
});

settingsFactoryRoot?.addEventListener("click", (event) => {
  const target = event.target;

  const linkedSurfaceTabButton = target.closest("[data-linked-surface-tab]");
  if (linkedSurfaceTabButton && settingsFactoryRoot.contains(linkedSurfaceTabButton)) {
    linkedSurfaceActiveTab = linkedSurfaceTabButton.dataset.linkedSurfaceTab;
    closeSettingsMenus();
    requestSettingsStateRender();
    return;
  }

  const linkedEditorModeLink = target.closest("[data-linked-editor-mode-link]");
  if (linkedEditorModeLink && settingsFactoryRoot.contains(linkedEditorModeLink)) {
    setEditorModeLinkState(!editorModeLinkedToTheme, { syncToTheme: !editorModeLinkedToTheme });
    return;
  }

  const linkedSurfaceModeButton = target.closest("[data-linked-surface-mode]");
  if (linkedSurfaceModeButton && settingsFactoryRoot.contains(linkedSurfaceModeButton)) {
    const nextMode = linkedSurfaceModeButton.dataset.linkedSurfaceMode;
    if (!nextMode) {
      return;
    }
    if (linkedSurfaceActiveTab === SURFACE_KEYS.THEME) {
      switchSurfaceMode(SURFACE_KEYS.THEME, nextMode);
      return;
    }
    if (editorModeLinkedToTheme) {
      requestSettingsStateRender();
      return;
    }
    switchSurfaceMode(SURFACE_KEYS.EDITOR, nextMode);
    return;
  }

  const glyphToggle = target.closest("[data-glyph-toggle]");
  if (glyphToggle && glyphColorList?.contains(glyphToggle)) {
    const key = glyphToggle.dataset.glyphToggle;
    openGlyphColorMenu = openGlyphColorMenu === key ? null : key;
    closeSettingsMenus("glyphColor");
    requestSettingsStateRender();
    return;
  }

  const glyphOption = target.closest("[data-glyph-option-key]");
  if (glyphOption && glyphColorList?.contains(glyphOption)) {
    const key = glyphOption.dataset.glyphOptionKey;
    dispatchSurfaceAction(SURFACE_ACTIONS.EDITOR_GLYPH_COLOR, () => {
      glyphColors[key] = normalizeHexColor(glyphOption.dataset.glyphOption, glyphColors[key]);
      openGlyphColorMenu = null;
    });
    return;
  }

  const dialogActionButton = target.closest(".setting-mini-button");
  if (
    dialogActionButton &&
    settingsFactoryRoot.contains(dialogActionButton) &&
    settingsDialogActionsById.has(dialogActionButton.id)
  ) {
    closeSettingsMenus();
    requestSettingsStateRender();
    handleSettingsDialogAction(dialogActionButton.id);
    return;
  }

  const dropdownOption = target.closest("[data-setting-option-for]");
  if (dropdownOption && settingsFactoryRoot.contains(dropdownOption)) {
    const optionsContainer = dropdownOption.closest(".palette-option-list");
    const dropdownNode =
      settingsDropdownNodesByOptionsId.get(optionsContainer?.id ?? "") ??
      settingsNodesById.get(dropdownOption.dataset.settingOptionFor);
    if (!dropdownNode || dropdownNode.kind !== "dropdown" || dropdownNode.variant === "glyphColor") {
      return;
    }
    applySettingsOptionSelection(
      dropdownOption.dataset.settingOptionFor,
      dropdownOption.dataset.settingOptionValue,
    );
    return;
  }

  const dropdownButton = target.closest("[data-setting-button-for]");
  if (dropdownButton && settingsFactoryRoot.contains(dropdownButton)) {
    const dropdownNode =
      settingsDropdownNodesByButtonId.get(dropdownButton.id) ??
      settingsNodesById.get(dropdownButton.dataset.settingButtonFor);
    if (!dropdownNode || dropdownNode.kind !== "dropdown" || dropdownNode.variant === "glyphColor") {
      return;
    }
    toggleSettingsMenu(dropdownNode.id);
    return;
  }

  const themeModeButton = target.closest("[data-theme-mode]");
  if (themeModeButton && settingsFactoryRoot.contains(themeModeButton)) {
    switchSurfaceMode(SURFACE_KEYS.THEME, themeModeButton.dataset.themeMode);
    return;
  }

  const editorModeButton = target.closest("[data-editor-mode]");
  if (editorModeButton && settingsFactoryRoot.contains(editorModeButton)) {
    switchSurfaceMode(SURFACE_KEYS.EDITOR, editorModeButton.dataset.editorMode);
    return;
  }

  const stepperButton = target.closest("[data-setting-step-for]");
  if (stepperButton && settingsFactoryRoot.contains(stepperButton)) {
    const stepperNode = settingsNodesById.get(stepperButton.dataset.settingStepFor);
    if (!stepperNode || stepperNode.kind !== "stepper") {
      return;
    }
    const direction = stepperButton.dataset.settingStepDirection === "decrease" ? -1 : 1;
    if (stepperNode.id === "interfaceSize") {
      stepInterfaceSize(direction);
      return;
    }
    if (stepperNode.id === "editorFontSize") {
      stepEditorFontSize(direction);
      return;
    }
  }

  const segmentButton = target.closest("[data-setting-segment-for='tabSize']");
  if (segmentButton && settingsFactoryRoot.contains(segmentButton)) {
    const segmentNode = settingsNodesById.get(segmentButton.dataset.settingSegmentFor);
    if (!segmentNode || segmentNode.kind !== "toggle") {
      return;
    }
    indentSize = Number(segmentButton.dataset.indentSize) || 2;
    closeSettingsMenus();
    persistEditorPreferences();
    updateIndentUi();
    requestSettingsStateRender();
    return;
  }

  const glyphToggleButton = target.closest("[data-setting-toggle-for='glyphComposition']");
  if (glyphToggleButton && settingsFactoryRoot.contains(glyphToggleButton)) {
    const toggleNode = settingsNodesById.get(glyphToggleButton.dataset.settingToggleFor);
    if (!toggleNode || toggleNode.kind !== "toggle") {
      return;
    }
    glyphsOn = !glyphsOn;
    document.body.classList.toggle("glyphs-off", !glyphsOn);
    toggleGlyphs.setAttribute("aria-pressed", String(glyphsOn));
    toggleGlyphs.setAttribute("aria-label", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
    toggleGlyphs.setAttribute("title", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
    closeSettingsMenus();
    persistEditorPreferences();
    requestSettingsStateRender();
    requestEditorContentRender();
  }
});

settingsFactoryRoot?.addEventListener("input", (event) => {
  const target = event.target;

  if (target.closest("[data-glyph-value]")) {
    const text = target.closest("[data-glyph-value]");
    const key = text.dataset.glyphValue;
    const normalized = normalizeHexColor(text.value, null);
    if (!normalized) {
      return;
    }

    dispatchSurfaceAction(
      SURFACE_ACTIONS.EDITOR_GLYPH_COLOR,
      () => {
        glyphColors[key] = normalized;
      },
      { closeMenus: false },
    );
    return;
  }

  if (target === autoSaveDelayInput) {
    const nextDelay = Number(autoSaveDelayInput.value);
    if (!Number.isFinite(nextDelay) || nextDelay < 250) {
      return;
    }

    autoSaveDelay = Math.round(nextDelay / 250) * 250;
    syncAutoSaveUi();
    persistAutoSaveState();
    if (autoSaveMode === "afterDelay") {
      scheduleAutoSave();
    }
  }
});

settingsFactoryRoot?.addEventListener("change", (event) => {
  const target = event.target;

  if (target.closest("[data-glyph-value]")) {
    const text = target.closest("[data-glyph-value]");
    const key = text.dataset.glyphValue;
    text.value = glyphColors[key].toUpperCase();
    return;
  }

  if (target === autoSaveDelayInput) {
    autoSaveDelayInput.value = String(autoSaveDelay);
  }
});

document.addEventListener("click", (event) => {
  if (!event.target.closest("#settingsFactoryRoot")) {
    closeSettingsMenus();
    requestSettingsStateRender();
  }

  if (!event.target.closest("#fileTree")) {
    if (openFileActionMenu !== null || pendingDeleteFile !== null) {
      openFileActionMenu = null;
      pendingDeleteFile = null;
      requestSidebarRender();
    }
  }
});

if (saveFile) {
  saveFile.addEventListener("click", () => {
    saveCurrentFile();
  });
}

editorInput.addEventListener("input", () => {
  fileSources[currentFile] = editorInput.value;
  fileDirty[currentFile] = true;
  scheduleAutoSave();
  requestSidebarRender();
  requestEditorContentRender();
});

editorInput.addEventListener("select", () => {
  requestEditorSelectionRender();
});

editorInput.addEventListener("scroll", () => {
  syncScroll();
});

editorInput.addEventListener("click", () => {
  requestEditorSelectionRender();
});

editorInput.addEventListener("blur", () => {
  if (autoSaveMode === "onFocusChange") {
    triggerAutoSave("focus-change");
  }
});

editorInput.addEventListener("keyup", () => {
  requestEditorSelectionRender();
});

editorInput.addEventListener("copy", (event) => {
  const selection = selectedSourceText();
  if (!selection) {
    return;
  }

  event.preventDefault();
  event.clipboardData?.setData("text/plain", selection);
});

editorInput.addEventListener("cut", (event) => {
  const { start, end } = normalizedSelectionRange();
  if (start === end) {
    return;
  }

  event.preventDefault();
  event.clipboardData?.setData("text/plain", selectedSourceText());
  editorInput.setSelectionRange(start, end);
  replaceSelection("", start);
});

editorInput.addEventListener("paste", (event) => {
  const pasted = event.clipboardData?.getData("text/plain");
  if (typeof pasted !== "string") {
    return;
  }

  event.preventDefault();
  const normalized = pasted.replace(/\r\n?/g, "\n");
  const { start } = normalizedSelectionRange();
  replaceSelection(normalized, start + normalized.length);
});

codeStage.addEventListener("mousedown", (event) => {
  if (event.button !== 0) {
    return;
  }

  event.preventDefault();

  if (!latestAnalysis) {
    return;
  }

  stopPointerSelection();
  const anchor = rawOffsetForPointer(event, latestAnalysis);
  editorInput.focus();
  if (event.detail >= 3) {
    const { start, end } = lineSelectionRangeForOffset(editorInput.value, anchor);
    editorInput.setSelectionRange(start, end);
    requestEditorSelectionRender();
    return;
  }

  if (event.detail === 2) {
    const charOffset = characterOffsetForPointer(event, latestAnalysis);
    const { start, end } = wordSelectionRangeForOffset(editorInput.value, charOffset);
    editorInput.setSelectionRange(start, end);
    requestEditorSelectionRender();
    return;
  }

  pointerSelectionAnchor = anchor;
  setSelectionFromAnchor(anchor, anchor);
  requestEditorSelectionRender();

  const handlePointerMove = (moveEvent) => {
    if (!latestAnalysis || pointerSelectionAnchor === null) {
      return;
    }

    const focus = rawOffsetForPointer(moveEvent, latestAnalysis);
    setSelectionFromAnchor(pointerSelectionAnchor, focus);
    requestEditorSelectionRender();
  };

  const handlePointerUp = (upEvent) => {
    if (!latestAnalysis || pointerSelectionAnchor === null) {
      stopPointerSelection();
      return;
    }

    const focus = rawOffsetForPointer(upEvent, latestAnalysis);
    setSelectionFromAnchor(pointerSelectionAnchor, focus);
    requestEditorSelectionRender();
    stopPointerSelection();
  };

  window.addEventListener("mousemove", handlePointerMove);
  window.addEventListener("mouseup", handlePointerUp, { once: true });
  pointerSelectionCleanup = () => {
    window.removeEventListener("mousemove", handlePointerMove);
    window.removeEventListener("mouseup", handlePointerUp);
  };
});

document.addEventListener("keydown", (event) => {
  if (!workspacePickerOverlay.hidden && event.key === "Escape") {
    event.preventDefault();
    closeWorkspacePicker();
    return;
  }

  if (document.activeElement !== editorInput) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      saveCurrentFile();
    }
    return;
  }

  if (event.key === "Tab") {
    event.preventDefault();
    if (event.shiftKey) {
      handleOutdent();
    } else {
      handleIndent();
    }
    return;
  }

  if (event.key === "Enter") {
    event.preventDefault();
    handleNewlineIndent();
    return;
  }

  if (event.key === "Backspace" && handleBackspaceIndent()) {
    event.preventDefault();
    return;
  }

  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    saveCurrentFile();
    return;
  }

  if (
    !event.altKey &&
    [
      "ArrowLeft",
      "ArrowRight",
      "ArrowUp",
      "ArrowDown",
      "Home",
      "End",
      "PageUp",
      "PageDown",
    ].includes(event.key)
  ) {
    scheduleNativeRender();
  }
});

window.addEventListener("beforeunload", (event) => {
  if (!Object.values(fileDirty).some(Boolean)) {
    return;
  }

  event.preventDefault();
  event.returnValue = "";
});

window.addEventListener("blur", () => {
  if (autoSaveMode === "onWindowChange") {
    triggerAutoSave("window-blur");
  }
});

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden" && autoSaveMode === "onWindowChange") {
    triggerAutoSave("visibility-change");
  }
});

async function bootstrap() {
  [primaryFile].forEach((fileName) => {
    fileDirty[fileName] = false;
  });

  installGridLayoutConfigDebugApi(window);
  loadLanguageState();
  applyLanguageUi();
  loadUiStyleState();
  loadThemeSettings();
  loadAutoSaveState();
  loadGlyphHighlightState();
  loadEditorPreferences();
  loadCustomPaletteConfigState();
  if (editorModeLinkedToTheme) {
    syncEditorModeToThemeSurface({ persist: false, requestRender: false });
  }
  document.body.classList.toggle("glyphs-off", !glyphsOn);
  ensureGridLayoutConfigBinding();
  applyUiStyleStrategy();
  toggleGlyphs.setAttribute("aria-pressed", String(glyphsOn));
  toggleGlyphs.setAttribute("aria-label", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
  toggleGlyphs.setAttribute("title", glyphsOn ? t("disableGlyphRendering") : t("enableGlyphRendering"));
  updateIndentUi();
  syncSidebar();
  await loadWorkspace();
  activeTreePath = "";
  editorInput.value = fileSources[currentFile] ?? "";
  flushFullAppRender();
}

bootstrap();
