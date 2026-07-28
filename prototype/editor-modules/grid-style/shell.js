export function createGridShellRefs(doc) {
  return {
    mainHead: doc.getElementById("gridMainHead"),
    title: doc.getElementById("gridCurrentFileTitle"),
    toggleButton: doc.getElementById("gridToggleSidebar"),
    closeButton: doc.getElementById("gridCloseSidebar"),
    fileTabs: doc.getElementById("gridFileTabs"),
    drawer: doc.getElementById("gridSideDrawer"),
    drawerTabsDock: doc.getElementById("gridDrawerTabsDock"),
    drawerMount: doc.getElementById("gridDrawerMount"),
    projectSidebar: doc.getElementById("gridProjectSidebar"),
    projectSidebarTitle: doc.getElementById("gridProjectSidebarTitle"),
    projectTreeMount: doc.getElementById("gridProjectTreeMount"),
    toggleProjectSidebarButton: doc.getElementById("gridToggleProjectSidebar"),
    toggleChatDockButton: doc.getElementById("gridToggleChatDock"),
    chatDock: doc.getElementById("gridChatDock"),
    chatDockTitle: doc.getElementById("gridChatDockTitle"),
    chatDockCollapseButton: doc.getElementById("gridChatDockCollapse"),
    chatMessages: doc.getElementById("gridChatMessages"),
    chatInput: doc.getElementById("gridChatInput"),
    chatSendButton: doc.getElementById("gridChatSend"),
  };
}

export function applyGridShellLabels(refs, t) {
  refs.title?.replaceChildren(docText(refs.title.ownerDocument, t("appTitle")));
  refs.toggleButton?.setAttribute("aria-label", t("openSidebar"));
  refs.toggleButton?.setAttribute("title", t("openSidebar"));
  refs.closeButton?.setAttribute("aria-label", t("closeSidebar"));
  refs.closeButton?.setAttribute("title", t("closeSidebar"));
}

export function syncGridShell(refs, { sidebarOpen, toggleIconMarkup, closeIconMarkup, t }) {
  refs.toggleButton?.setAttribute("aria-expanded", String(sidebarOpen));
  refs.toggleButton?.setAttribute("aria-label", t("openSidebar"));
  refs.toggleButton?.setAttribute("title", t("openSidebar"));
  refs.closeButton?.setAttribute("aria-label", t("closeSidebar"));
  refs.closeButton?.setAttribute("title", t("closeSidebar"));

  if (refs.toggleButton && typeof toggleIconMarkup === "string") {
    refs.toggleButton.innerHTML = toggleIconMarkup;
  }
  if (refs.closeButton && typeof closeIconMarkup === "string") {
    refs.closeButton.innerHTML = closeIconMarkup;
  }
}

export function bindGridShellEvents(refs, { onToggle, onClose }) {
  refs.toggleButton?.addEventListener("click", onToggle);
  refs.closeButton?.addEventListener("click", onClose);
}

function docText(doc, value) {
  return doc.createTextNode(value);
}
