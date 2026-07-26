export const EDITORIAL_STYLE_KEY = "editorial";
export const GRID_STYLE_KEY = "grid";

export function isEditorialStyle(styleKey) {
  return styleKey === EDITORIAL_STYLE_KEY;
}

export function isGridStyle(styleKey) {
  return styleKey === GRID_STYLE_KEY;
}

function restoreDrawerPanels({ sharedDrawerListShell, drawerPanelFiles, drawerPanelSettings }) {
  if (!sharedDrawerListShell) {
    return;
  }

  if (drawerPanelFiles && drawerPanelFiles.parentElement !== sharedDrawerListShell) {
    sharedDrawerListShell.appendChild(drawerPanelFiles);
  }
  if (drawerPanelSettings && drawerPanelSettings.parentElement !== sharedDrawerListShell) {
    sharedDrawerListShell.appendChild(drawerPanelSettings);
  }
}

export function mountSharedDrawerContent({
  activeUiStyleKey,
  sharedDrawerContent,
  sharedDrawerListShell,
  gridDrawerMount,
  editorialDrawerMount,
  gridProjectTreeMount,
  drawerPanelFiles,
  drawerPanelSettings,
}) {
  if (!sharedDrawerContent) {
    return;
  }

  if (isGridStyle(activeUiStyleKey) && gridProjectTreeMount && gridDrawerMount) {
    // Grid runs the IDE shell: the files panel lives in the left project
    // sidebar, the settings panel lives in the right drawer, and the emptied
    // shared shell is parked (and hidden) inside the drawer mount.
    if (drawerPanelFiles && drawerPanelFiles.parentElement !== gridProjectTreeMount) {
      gridProjectTreeMount.appendChild(drawerPanelFiles);
    }
    if (drawerPanelSettings && drawerPanelSettings.parentElement !== gridDrawerMount) {
      gridDrawerMount.appendChild(drawerPanelSettings);
    }
    if (sharedDrawerContent.parentElement !== gridDrawerMount) {
      gridDrawerMount.appendChild(sharedDrawerContent);
    }
    return;
  }

  restoreDrawerPanels({ sharedDrawerListShell, drawerPanelFiles, drawerPanelSettings });

  const targetMount = isEditorialStyle(activeUiStyleKey) ? editorialDrawerMount : gridDrawerMount;
  if (!targetMount || sharedDrawerContent.parentElement === targetMount) {
    return;
  }

  targetMount.appendChild(sharedDrawerContent);
}

export function mountSharedDrawerTabs({
  activeUiStyleKey,
  sharedDrawerTabs,
  sharedDrawerListShell,
  gridDrawerTabsDock,
}) {
  if (!sharedDrawerTabs || !sharedDrawerListShell) {
    return;
  }

  if (isEditorialStyle(activeUiStyleKey) || !gridDrawerTabsDock) {
    if (sharedDrawerTabs.parentElement === sharedDrawerListShell) {
      return;
    }
    const firstDrawerPanel = sharedDrawerListShell.querySelector(".drawer-panel");
    sharedDrawerListShell.insertBefore(sharedDrawerTabs, firstDrawerPanel ?? sharedDrawerListShell.firstChild);
    return;
  }

  if (sharedDrawerTabs.parentElement === gridDrawerTabsDock) {
    return;
  }

  gridDrawerTabsDock.appendChild(sharedDrawerTabs);
}

export function syncShellVisibility({
  activeUiStyleKey,
  gridMainHead,
  gridFileTabs,
  gridSidebar,
  editorialMainTitle,
  editorialSidebar,
  editorialRail,
}) {
  const editorialActive = isEditorialStyle(activeUiStyleKey);
  const gridActive = !editorialActive;

  if (gridMainHead) {
    gridMainHead.hidden = !gridActive;
  }
  if (gridFileTabs) {
    gridFileTabs.hidden = !gridActive;
  }
  if (gridSidebar) {
    gridSidebar.hidden = !gridActive;
    gridSidebar.setAttribute("aria-hidden", String(!gridActive));
  }
  if (editorialMainTitle) {
    editorialMainTitle.hidden = !editorialActive;
  }
  if (editorialSidebar) {
    editorialSidebar.hidden = !editorialActive;
    editorialSidebar.setAttribute("aria-hidden", String(!editorialActive));
  }
  if (editorialRail) {
    editorialRail.hidden = !editorialActive;
    editorialRail.setAttribute("aria-hidden", String(!editorialActive));
  }
}
