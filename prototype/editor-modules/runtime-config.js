import { AUTO_SAVE_MODES, DRAWER_TABS, LANGUAGE_KEYS, SURFACE_KEYS, THEME_MODES } from "./enums.js";

export const workspaceApiBase = "/api/workspace";
export const primaryFile = "main.styio";
export const defaultCreateLeafNames = {
  file: "new_file.styio",
  folder: "new_folder",
};
export const fallbackSources = {
  "main.styio": `pipeline mainFlow
let staged := source |> normalize
let routeOut = staged -> render
let routeIn = source <- bridge
let promote = state => running
let fallback = state <= idle
fn main(input) {
  state idle
  when input.ready -> state running
  emit staged
}`,
};

export const storageKeys = {
  glyphHighlight: "Vityo:glyph-highlights",
  autoSave: "Vityo:auto-save",
  language: "Vityo:language",
  uiStyle: "Vityo:ui-style",
  themeSettings: "Vityo:theme-settings",
  editorSettings: "Vityo:editor-settings",
  customPaletteConfig: "Vityo:custom-palette-config",
};

export const customPaletteConfigSchema = "https://styio.dev/schemas/theme-customizations.json";

export function createInitialRuntimeState() {
  return {
    fileOrder: [primaryFile],
    currentFile: primaryFile,
    glyphsOn: true,
    workspaceApiAvailable: false,
    workspaceRootPath: "",
    workspaceName: "workspace",
    workspaceEntries: [],
    workspaceFiles: [primaryFile],
    workspaceLoadedFiles: new Set(),
    saveInFlight: false,
    latestAnalysis: null,
    sidebarOpen: false,
    activeDrawerTab: DRAWER_TABS.FILES,
    linkedSurfaceActiveTab: SURFACE_KEYS.THEME,
    editorModeLinkedToTheme: true,
    indentSize: 2,
    activeLanguageKey: LANGUAGE_KEYS.ZH_CN,
    languageMenuOpen: false,
    activeUiStyleKey: "grid",
    styleMenuOpen: false,
    autoSaveMode: AUTO_SAVE_MODES.AFTER_DELAY,
    autoSaveDelay: 1000,
    autoSaveMenuOpen: false,
    themeMode: THEME_MODES.DARK,
    themePaletteMenuOpen: false,
    themeColorMenuOpen: false,
    themeBackgroundMenuOpen: false,
    interfaceFontMenuOpen: false,
    themeTextMenuOpen: false,
    themeLineMenuOpen: false,
    editorFontMenuOpen: false,
    openGlyphColorMenu: null,
    paletteMenuOpen: false,
    editorBackgroundMenuOpen: false,
    textColorMenuOpen: false,
    textHighlightMenuOpen: false,
    blockSurfaceMenuOpen: false,
    lineHighlightMenuOpen: false,
    selectionHighlightMenuOpen: false,
    editorMode: THEME_MODES.DARK,
    activeThemePaletteKey: "graphiteGold",
    activeThemeColorKey: "defaultGold",
    activeThemeBackgroundKey: "graphite",
    activeThemeTextKey: "mist",
    activeInterfaceFontKey: "defaultSans",
    activeInterfaceSizeKey: "15",
    activeEditorFontKey: "jetbrainsMono",
    activeEditorFontSizeKey: "15",
    activePaletteKey: "default",
    activeEditorBackgroundKey: "graphite",
    activeEditorTextColorKey: "mist",
    activeEditorTextHighlightKey: "defaultGold",
    activeThemeLineKey: "soft",
    activeBlockSurfaceKey: "graphite",
    activeLineHighlightKey: "graphite",
    activeSelectionHighlightKey: "graphite",
    visualTokenOverrides: {},
    workspacePickerPath: "",
    workspacePickerParentPath: null,
    workspacePickerMode: "directory",
    workspacePickerIncludeFiles: false,
    workspacePickerSelectedFilePath: "",
    workspacePickerConfirmAction: null,
    workspacePickerTitleText: "",
    workspacePickerDefaultCaptionText: "",
    workspacePickerConfirmText: "",
    openFileActionMenu: null,
    pendingDeleteFile: null,
    bulkDeleteMode: false,
    selectedTreePaths: new Set(),
    activeTreePath: "",
    expandedTreePaths: new Set(),
  };
}
