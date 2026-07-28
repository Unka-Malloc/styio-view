import {
  mountSharedDrawerContent,
  mountSharedDrawerTabs,
  syncShellVisibility,
} from "./style-shell-common.js";
import {
  applyGridShellLabels,
  bindGridShellEvents,
  createGridShellRefs,
  syncGridShell,
} from "../grid-style/shell.js";
import {
  applyEditorialShellLabels,
  bindEditorialShellEvents,
  createEditorialShellRefs,
  syncEditorialShell,
} from "../editorial-style/shell.js";

export function createStyleShellBridge(doc) {
  return {
    sharedDrawerContent: doc.getElementById("sharedDrawerContent"),
    sharedDrawerListShell: doc.getElementById("sharedDrawerListShell"),
    sharedDrawerTabs: doc.getElementById("sharedDrawerTabs"),
    drawerPanelFiles: doc.getElementById("drawerPanelFiles"),
    drawerPanelSettings: doc.getElementById("drawerPanelSettings"),
    gridRefs: createGridShellRefs(doc),
    editorialRefs: createEditorialShellRefs(doc),
  };
}

export function applyStyleShellLabels(bridge, t) {
  applyGridShellLabels(bridge.gridRefs, t);
  applyEditorialShellLabels(bridge.editorialRefs, t);
}

export function bindStyleShellBridgeEvents(
  bridge,
  { onGridToggle, onGridClose, onEditorialToggle, onEditorialFiles, onEditorialSettings },
) {
  bindGridShellEvents(bridge.gridRefs, {
    onToggle: onGridToggle,
    onClose: onGridClose,
  });
  bindEditorialShellEvents(bridge.editorialRefs, {
    onToggle: onEditorialToggle,
    onFiles: onEditorialFiles,
    onSettings: onEditorialSettings,
  });
}

export function syncStyleShellLayout(
  bridge,
  { activeUiStyleKey, sidebarOpen, toggleIconMarkup, closeIconMarkup, t },
) {
  mountSharedDrawerContent({
    activeUiStyleKey,
    sharedDrawerContent: bridge.sharedDrawerContent,
    sharedDrawerListShell: bridge.sharedDrawerListShell,
    gridDrawerMount: bridge.gridRefs.drawerMount,
    editorialDrawerMount: bridge.editorialRefs.drawerMount,
    gridProjectTreeMount: bridge.gridRefs.projectTreeMount,
    drawerPanelFiles: bridge.drawerPanelFiles,
    drawerPanelSettings: bridge.drawerPanelSettings,
  });
  mountSharedDrawerTabs({
    activeUiStyleKey,
    sharedDrawerTabs: bridge.sharedDrawerTabs,
    sharedDrawerListShell: bridge.sharedDrawerListShell,
    gridDrawerTabsDock: bridge.gridRefs.drawerTabsDock,
  });
  syncShellVisibility({
    activeUiStyleKey,
    gridMainHead: bridge.gridRefs.mainHead,
    gridFileTabs: bridge.gridRefs.fileTabs,
    gridSidebar: bridge.gridRefs.drawer,
    editorialMainTitle: bridge.editorialRefs.mainTitle,
    editorialSidebar: bridge.editorialRefs.sidebar,
    editorialRail: bridge.editorialRefs.rail,
  });
  syncGridShell(bridge.gridRefs, {
    sidebarOpen,
    toggleIconMarkup,
    closeIconMarkup,
    t,
  });
  syncEditorialShell(bridge.editorialRefs, {
    sidebarOpen,
    t,
  });
}

export function syncStyleShellTitles(bridge, { appTitle, workspaceTitle }) {
  setNodeText(bridge.gridRefs.title, appTitle);
  setNodeText(bridge.editorialRefs.brandTitle, appTitle);
  setNodeText(bridge.editorialRefs.sidebarTitle, workspaceTitle);
}

function setNodeText(node, value) {
  if (node) {
    node.textContent = value;
  }
}
