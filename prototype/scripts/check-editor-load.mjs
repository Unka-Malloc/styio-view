#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import http from "node:http";
import https from "node:https";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { chromium } from "playwright-core";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROTOTYPE_ROOT = path.resolve(__dirname, "..");
const DEFAULT_URL = process.env.STYIO_EDITOR_URL ?? "http://127.0.0.1:4180/editor";
const CHROME_PATH =
  process.env.STYIO_CHROME_PATH ??
  process.env.CHROME_EXECUTABLE ??
  "/usr/bin/chromium";
const PYTHON_BIN = process.env.PYTHON_BIN ?? "python3";
const ARTIFACT_DIR = path.join(PROTOTYPE_ROOT, ".artifacts");
const SCREENSHOT_PATH = path.join(ARTIFACT_DIR, "editor-load-failure.png");
const SERVER_READY_TIMEOUT_MS = 15000;
const SIDEBAR_TOGGLE_SELECTOR = '[data-shell-sidebar-toggle="true"]';

function log(message) {
  process.stdout.write(`${message}\n`);
}

function fail(message) {
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}

async function ensureArtifactDir() {
  await fs.mkdir(ARTIFACT_DIR, { recursive: true });
}

async function canReach(url) {
  return new Promise((resolve) => {
    let parsed;
    try {
      parsed = new URL(url);
    } catch {
      resolve(false);
      return;
    }
    const client = parsed.protocol === "https:" ? https : http;
    const request = client.request(
      parsed,
      { method: "GET", timeout: 2000 },
      (response) => {
        response.resume();
        response.on("end", () => {
          const status = response.statusCode ?? 0;
          resolve(status >= 200 && status < 400);
        });
      },
    );
    request.on("timeout", () => {
      request.destroy();
      resolve(false);
    });
    request.on("error", () => resolve(false));
    request.end();
  });
}

async function waitForReachable(url, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await canReach(url)) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  return false;
}

async function ensureServer(url) {
  if (await canReach(url)) {
    return { child: null, started: false };
  }

  log("editor url is not reachable, starting prototype/dev_server.py");
  const child = spawn(PYTHON_BIN, ["dev_server.py"], {
    cwd: PROTOTYPE_ROOT,
    stdio: ["ignore", "pipe", "pipe"],
  });

  child.stdout.on("data", (chunk) => {
    process.stdout.write(`[selftest:server] ${chunk}`);
  });
  child.stderr.on("data", (chunk) => {
    process.stderr.write(`[selftest:server] ${chunk}`);
  });

  const ready = await waitForReachable(url, SERVER_READY_TIMEOUT_MS);
  if (!ready) {
    child.kill("SIGTERM");
    throw new Error(`dev server did not become ready within ${SERVER_READY_TIMEOUT_MS}ms`);
  }

  return { child, started: true };
}

async function runSelfTest() {
  if (!(await fs.stat(CHROME_PATH).then(() => true).catch(() => false))) {
    throw new Error(`chrome executable not found: ${CHROME_PATH}`);
  }

  const server = await ensureServer(DEFAULT_URL);
  const browser = await chromium.launch({
    headless: true,
    executablePath: CHROME_PATH,
    args: ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check"],
  });

  const page = await browser.newPage({
    viewport: { width: 1440, height: 1200 },
  });

  const consoleErrors = [];
  const consoleWarnings = [];
  const requestFailures = [];
  const pageErrors = [];
  let currentStep = "boot";
  const expectedStyles = [
    { key: "grid", label: "Grid", cssVar: "--style-toggle-radius", expectedValue: "10px" },
    {
      key: "editorial",
      label: "Editorial",
      cssVar: "--title-font-family",
      expectedValue: "\"Iowan Old Style\", \"Palatino Linotype\", \"Book Antiqua\", serif",
    },
  ];

  async function runStep(name, fn) {
    currentStep = name;
    log(`step: ${name}`);
    return await fn();
  }

  async function openStyleMenu() {
    const isOpen = await page.evaluate(() => document.getElementById("styleOptions")?.classList.contains("is-open") === true);
    if (!isOpen) {
      await page.click("#styleButton");
    }
    await page.waitForFunction(() => document.getElementById("styleOptions")?.classList.contains("is-open"), null, {
      timeout: 10000,
    });
  }

  async function selectStyle(styleSpec) {
    await openStyleMenu();
    await page.click(`[data-setting-option-for="style"][data-setting-option-value="${styleSpec.key}"]`);
    await page.waitForFunction(
      ({ key, label, cssVar, expectedValue }) => {
        const buttonLabel = document.getElementById("styleButton")?.textContent?.trim();
        const activeStyle = document.body.dataset.uiStyle;
        const cssValue = getComputedStyle(document.documentElement).getPropertyValue(cssVar).trim();
        return buttonLabel === label && activeStyle === key && cssValue === expectedValue;
      },
      styleSpec,
      { timeout: 10000 },
    );
  }

  async function clickVisibleSidebarToggle() {
    const toggles = page.locator(SIDEBAR_TOGGLE_SELECTOR);
    const count = await toggles.count();
    for (let index = 0; index < count; index += 1) {
      const toggle = toggles.nth(index);
      if (await toggle.isVisible()) {
        await toggle.click();
        return;
      }
    }
    throw new Error(`no visible sidebar toggle matched ${SIDEBAR_TOGGLE_SELECTOR}`);
  }

  async function captureGridShellGeometry() {
    return await page.evaluate(() => {
      const rect = (selector) => {
        const node = document.querySelector(selector);
        if (!node) {
          return null;
        }
        const box = node.getBoundingClientRect();
        return {
          selector,
          top: box.top,
          right: box.right,
          bottom: box.bottom,
          left: box.left,
          width: box.width,
          height: box.height,
        };
      };
      const insetTop = (outer, inner) => inner.top - outer.top;
      const insetRight = (outer, inner) => outer.right - inner.right;
      const centerTopInset = (outer, inner) => inner.top + inner.height / 2 - outer.top;
      const centerRightInset = (outer, inner) => outer.right - (inner.left + inner.width / 2);
      const bodyStyle = getComputedStyle(document.body);
      const cssPxVar = (name) => Number.parseFloat(bodyStyle.getPropertyValue(name)) || 0;
      const cssNumberVar = (name) => Number.parseFloat(bodyStyle.getPropertyValue(name)) || 0;

      const mainCard = rect(".main-editor-card");
      const toolbar = rect("#gridMainToolbar");
      const toolbarSpacer = rect("#gridMainToolbarSpacer");
      const fileTabs = rect("#gridFileTabs");
      const openButton = rect("#gridToggleSidebar");
      const editorFrame = rect(".main-editor-card .editor-frame");
      const sideDrawer = rect("#gridSideDrawer");
      const drawerHeader = rect("#gridDrawerHeader");
      const drawerHeaderSpacer = rect("#gridDrawerHeaderSpacer");
      const drawerTabs = rect("#sharedDrawerTabs");
      const closeButton = rect("#gridCloseSidebar");
      const drawerMount = rect("#gridDrawerMount");

      if (
        !mainCard ||
        !toolbar ||
        !toolbarSpacer ||
        !fileTabs ||
        !openButton ||
        !editorFrame ||
        !sideDrawer ||
        !drawerHeader ||
        !drawerHeaderSpacer ||
        !drawerTabs ||
        !closeButton ||
        !drawerMount
      ) {
        return null;
      }

      return {
        expectedBlockStartInset: cssPxVar("--grid-shell-block-start-inset"),
        expectedInlineInset: cssPxVar("--grid-shell-inline-inset"),
        expectedSectionGap: cssPxVar("--grid-shell-section-gap"),
        innerOuterMarginConsistent: cssNumberVar("--grid-shell-inner-outer-margin-consistent") === 1,
        innerMarginScale: cssNumberVar("--grid-shell-inner-margin-scale"),
        outerMarginScale: cssNumberVar("--grid-shell-outer-margin-scale"),
        toolbarHeight: toolbar.height,
        fileTabsHeight: fileTabs.height,
        toolbarTopInset: insetTop(mainCard, toolbar),
        fileTabsCenterTopInset: centerTopInset(mainCard, fileTabs),
        toolbarSpacerHeight: toolbarSpacer.height,
        openButtonTopInset: insetTop(mainCard, openButton),
        openButtonRightInset: insetRight(mainCard, openButton),
        openButtonCenterTopInset: centerTopInset(mainCard, openButton),
        openButtonCenterRightInset: centerRightInset(mainCard, openButton),
        editorLeftInset: editorFrame.left - mainCard.left,
        editorRightInset: mainCard.right - editorFrame.right,
        editorBottomInset: mainCard.bottom - editorFrame.bottom,
        drawerWidth: sideDrawer.width,
        headerHeight: drawerHeader.height,
        headerChildHeight: Math.max(drawerTabs.height, closeButton.height),
        headerTopInset: insetTop(sideDrawer, drawerHeader),
        headerSpacerHeight: drawerHeaderSpacer.height,
        drawerTabsCenterTopInset: centerTopInset(sideDrawer, drawerTabs),
        closeButtonTopInset: insetTop(sideDrawer, closeButton),
        closeButtonRightInset: insetRight(sideDrawer, closeButton),
        closeButtonCenterTopInset: centerTopInset(sideDrawer, closeButton),
        closeButtonCenterRightInset: centerRightInset(sideDrawer, closeButton),
        drawerContentLeftInset: drawerMount.left - sideDrawer.left,
        drawerContentRightInset: sideDrawer.right - drawerMount.right,
        drawerContentBottomInset: sideDrawer.bottom - drawerMount.bottom,
      };
    });
  }

  async function waitForGridDrawerState(open) {
    await page.waitForFunction(
      (expectedOpen) => {
        const drawer = document.getElementById("gridSideDrawer");
        if (!drawer) {
          return false;
        }
        const style = getComputedStyle(document.body);
        const expectedVar = expectedOpen ? "--grid-sidebar-width-open" : "--grid-sidebar-width-closed";
        const expectedWidth = Number.parseFloat(style.getPropertyValue(expectedVar)) || 0;
        const actualWidth = drawer.getBoundingClientRect().width;
        return Math.abs(actualWidth - expectedWidth) <= 1;
      },
      open,
      { timeout: 10000 },
    );
  }

  page.on("console", (message) => {
    const type = message.type();
    const text = message.text();
    if (type === "error") {
      consoleErrors.push(text);
      return;
    }
    if (type === "warning") {
      consoleWarnings.push(text);
    }
  });

  page.on("pageerror", (error) => {
    pageErrors.push(error?.stack || error?.message || String(error));
  });

  page.on("requestfailed", (request) => {
    requestFailures.push(`${request.method()} ${request.url()} :: ${request.failure()?.errorText ?? "unknown"}`);
  });

  try {
    log(`opening ${DEFAULT_URL}`);
    const response = await runStep("open-page", () =>
      page.goto(DEFAULT_URL, {
        waitUntil: "networkidle",
        timeout: 20000,
      }),
    );
    if (!response?.ok()) {
      throw new Error(`page load returned ${response?.status() ?? "unknown status"}`);
    }

    await runStep("wait-shell", () => page.waitForSelector("#workspaceShell", { timeout: 10000 }));
    await runStep("wait-toggle-sidebar", () =>
      page.waitForSelector(SIDEBAR_TOGGLE_SELECTOR, { state: "visible", timeout: 10000 }),
    );
    await runStep("wait-render-layer", () => page.waitForSelector("#renderLayer", { timeout: 10000 }));
    await runStep("wait-settings-root-attached", () =>
      page.waitForSelector("#settingsFactoryRoot", { state: "attached", timeout: 10000 }),
    );

    await runStep("open-sidebar", async () => {
      const alreadyOpen = await page.evaluate(() => document.body.classList.contains("sidebar-open"));
      if (!alreadyOpen) {
        await clickVisibleSidebarToggle();
      }
      await page.waitForFunction(() => document.body.classList.contains("sidebar-open"), null, { timeout: 10000 });
    });

    await runStep("switch-to-settings-tab", async () => {
      await page.click('[data-drawer-tab="settings"]');
      await page.waitForFunction(() => document.getElementById("drawerPanelSettings")?.classList.contains("is-active"), null, {
        timeout: 10000,
      });
      await page.waitForSelector("#settingsFactoryRoot", { state: "visible", timeout: 10000 });
    });

    await runStep("wait-theme-editor-controls", async () => {
      await page.waitForSelector("#linkedSurfaceModeCard", { timeout: 10000 });
      await page.waitForSelector("#linkedSurfaceThemePanel", { timeout: 10000 });
      await page.waitForSelector("#linkedSurfaceModeToggle", { timeout: 10000 });
      await page.waitForSelector("#styleButton", { timeout: 10000 });
      await page.waitForSelector("#styleOptions", { state: "attached", timeout: 10000 });
      await page.waitForSelector("#themePaletteButton", { timeout: 10000 });
      await page.waitForSelector("#interfaceFontButton", { timeout: 10000 });
    });

    await runStep("verify-style-options", async () => {
      await openStyleMenu();
      await page.waitForFunction(
        (styles) => {
          const options = Array.from(document.querySelectorAll('[data-setting-option-for="style"]'));
          if (options.length !== styles.length) {
            return false;
          }
          return options.every((option, index) => option.dataset.settingOptionValue === styles[index].key);
        },
        expectedStyles,
        { timeout: 10000 },
      );
    });

    await runStep("cycle-style-presets", async () => {
      for (const styleSpec of expectedStyles) {
        await selectStyle(styleSpec);
      }

      await selectStyle(expectedStyles[1]);
    });

    await runStep("verify-grid-shell-geometry", async () => {
      await selectStyle(expectedStyles[0]);
      await page.waitForFunction(() => document.body.dataset.uiStyle === "grid", null, { timeout: 10000 });

      if (await page.evaluate(() => document.body.classList.contains("sidebar-open"))) {
        await page.click("#gridCloseSidebar");
        await page.waitForFunction(() => !document.body.classList.contains("sidebar-open"), null, { timeout: 10000 });
        await waitForGridDrawerState(false);
      }

      const collapsed = await captureGridShellGeometry();
      if (!collapsed) {
        throw new Error("failed to capture collapsed grid shell geometry");
      }

      await page.click("#gridToggleSidebar");
      await page.waitForFunction(() => document.body.classList.contains("sidebar-open"), null, { timeout: 10000 });
      await waitForGridDrawerState(true);

      const expanded = await captureGridShellGeometry();
      if (!expanded) {
        throw new Error("failed to capture expanded grid shell geometry");
      }

      const tolerance = 1.1;
      const checks = [
        ["toolbar/file-tabs height", collapsed.toolbarHeight, collapsed.fileTabsHeight],
        ["toolbar top inset", collapsed.toolbarTopInset, collapsed.expectedBlockStartInset],
        ["header top inset", expanded.headerTopInset, expanded.expectedBlockStartInset],
        ["toolbar spacer height", collapsed.toolbarSpacerHeight, collapsed.expectedSectionGap],
        ["header spacer height", expanded.headerSpacerHeight, expanded.expectedSectionGap],
        ["header child height", expanded.headerHeight, expanded.headerChildHeight],
        ["toolbar/header top inset", collapsed.toolbarTopInset, expanded.headerTopInset],
        ["open button top inset", collapsed.openButtonTopInset, collapsed.expectedBlockStartInset],
        ["close button top inset", expanded.closeButtonTopInset, expanded.expectedBlockStartInset],
        ["open/close top inset", collapsed.openButtonTopInset, expanded.closeButtonTopInset],
        ["open button right inset", collapsed.openButtonRightInset, collapsed.expectedInlineInset],
        ["close button right inset", expanded.closeButtonRightInset, expanded.expectedInlineInset],
        ["open/close right inset", collapsed.openButtonRightInset, expanded.closeButtonRightInset],
        ["open/close center-top inset", collapsed.openButtonCenterTopInset, expanded.closeButtonCenterTopInset],
        ["open/close center-right inset", collapsed.openButtonCenterRightInset, expanded.closeButtonCenterRightInset],
        ["tabs center-top inset", collapsed.fileTabsCenterTopInset, expanded.drawerTabsCenterTopInset],
        ["editor left inset", collapsed.editorLeftInset, collapsed.expectedInlineInset],
        ["editor right inset", collapsed.editorRightInset, collapsed.expectedInlineInset],
        ["editor bottom inset", collapsed.editorBottomInset, collapsed.expectedBlockStartInset],
        ["drawer content left inset", expanded.drawerContentLeftInset, expanded.expectedInlineInset],
        ["drawer content right inset", expanded.drawerContentRightInset, expanded.expectedInlineInset],
        ["drawer content bottom inset", expanded.drawerContentBottomInset, expanded.expectedBlockStartInset],
      ];
      if (collapsed.innerOuterMarginConsistent || expanded.innerOuterMarginConsistent) {
        checks.push(["consistent section gap", collapsed.expectedSectionGap, collapsed.expectedBlockStartInset]);
        checks.push(["consistent section gap expanded", expanded.expectedSectionGap, expanded.expectedBlockStartInset]);
      }
      const failures = checks
        .filter(([, actual, expected]) => Math.abs(actual - expected) > tolerance)
        .map(([label, actual, expected]) => `${label}: ${actual.toFixed(2)} vs ${expected.toFixed(2)}`);

      if (expanded.drawerWidth <= 0) {
        failures.push(`drawer width: ${expanded.drawerWidth.toFixed(2)} vs > 0`);
      }

      if (failures.length) {
        throw new Error(`grid shell geometry drifted\n- ${failures.join("\n- ")}`);
      }

      await page.click('[data-drawer-tab="settings"]');
      await page.waitForFunction(() => document.getElementById("drawerPanelSettings")?.classList.contains("is-active"), null, {
        timeout: 10000,
      });
    });

    await runStep("verify-grid-layout-config-store", async () => {
      await selectStyle(expectedStyles[0]);
      await page.waitForFunction(() => document.body.dataset.uiStyle === "grid", null, { timeout: 10000 });

      if (await page.evaluate(() => document.body.classList.contains("sidebar-open"))) {
        await page.click("#gridCloseSidebar");
        await page.waitForFunction(() => !document.body.classList.contains("sidebar-open"), null, { timeout: 10000 });
        await waitForGridDrawerState(false);
      }

      const baseline = await captureGridShellGeometry();
      if (!baseline) {
        throw new Error("failed to capture baseline grid shell geometry");
      }

      const updatedState = await page.evaluate(() => {
        const api = window.__styioGridLayoutConfig;
        if (!api) {
          return null;
        }

        const before = api.getSnapshot();
        const after = api.update({
          outer_margin: before.outer_margin * 1.1,
        });
        return {
          before,
          after,
        };
      });

      if (!updatedState) {
        throw new Error("grid layout config store debug api unavailable");
      }

      const expectedUpdated = {
        blockStartInset: updatedState.after.shell_vertical_inset_base * updatedState.after.outer_margin,
        inlineInset: updatedState.after.shell_inline_inset_base * updatedState.after.outer_margin,
        sectionGap:
          updatedState.after.shell_vertical_inset_base *
          (updatedState.after.inner_outer_margin_consistent ? updatedState.after.outer_margin : updatedState.after.inner_margin),
      };

      await page.waitForFunction(
        (expected) => {
          const style = getComputedStyle(document.body);
          const blockStartInset = Number.parseFloat(style.getPropertyValue("--grid-shell-block-start-inset")) || 0;
          const inlineInset = Number.parseFloat(style.getPropertyValue("--grid-shell-inline-inset")) || 0;
          const sectionGap = Number.parseFloat(style.getPropertyValue("--grid-shell-section-gap")) || 0;
          return (
            Math.abs(blockStartInset - expected.blockStartInset) < 0.2 &&
            Math.abs(inlineInset - expected.inlineInset) < 0.2 &&
            Math.abs(sectionGap - expected.sectionGap) < 0.2
          );
        },
        expectedUpdated,
        { timeout: 10000 },
      );

      const updatedGeometry = await captureGridShellGeometry();
      if (!updatedGeometry) {
        throw new Error("failed to capture updated grid shell geometry");
      }

      const updatedFailures = [
        ["updated toolbar top inset", updatedGeometry.toolbarTopInset, expectedUpdated.blockStartInset],
        ["updated toolbar spacer", updatedGeometry.toolbarSpacerHeight, expectedUpdated.sectionGap],
        ["updated open button top inset", updatedGeometry.openButtonTopInset, expectedUpdated.blockStartInset],
        ["updated open button right inset", updatedGeometry.openButtonRightInset, expectedUpdated.inlineInset],
      ]
        .filter(([, actual, expected]) => Math.abs(actual - expected) > 0.6)
        .map(([label, actual, expected]) => `${label}: ${actual.toFixed(2)} vs ${expected.toFixed(2)}`);

      if (updatedFailures.length) {
        throw new Error(`grid layout config update drifted\n- ${updatedFailures.join("\n- ")}`);
      }

      const resetState = await page.evaluate(() => {
        const api = window.__styioGridLayoutConfig;
        return api?.reset() ?? null;
      });

      if (!resetState) {
        throw new Error("grid layout config store reset unavailable");
      }

      const expectedReset = {
        blockStartInset: resetState.shell_vertical_inset_base * resetState.outer_margin,
        inlineInset: resetState.shell_inline_inset_base * resetState.outer_margin,
        sectionGap:
          resetState.shell_vertical_inset_base *
          (resetState.inner_outer_margin_consistent ? resetState.outer_margin : resetState.inner_margin),
      };

      await page.waitForFunction(
        (expected) => {
          const style = getComputedStyle(document.body);
          const blockStartInset = Number.parseFloat(style.getPropertyValue("--grid-shell-block-start-inset")) || 0;
          const inlineInset = Number.parseFloat(style.getPropertyValue("--grid-shell-inline-inset")) || 0;
          const sectionGap = Number.parseFloat(style.getPropertyValue("--grid-shell-section-gap")) || 0;
          return (
            Math.abs(blockStartInset - expected.blockStartInset) < 0.2 &&
            Math.abs(inlineInset - expected.inlineInset) < 0.2 &&
            Math.abs(sectionGap - expected.sectionGap) < 0.2
          );
        },
        expectedReset,
        { timeout: 10000 },
      );

      const resetGeometry = await captureGridShellGeometry();
      if (!resetGeometry) {
        throw new Error("failed to capture reset grid shell geometry");
      }

      const resetFailures = [
        ["reset toolbar top inset", resetGeometry.toolbarTopInset, baseline.toolbarTopInset],
        ["reset toolbar spacer", resetGeometry.toolbarSpacerHeight, baseline.toolbarSpacerHeight],
        ["reset open button top inset", resetGeometry.openButtonTopInset, baseline.openButtonTopInset],
        ["reset open button right inset", resetGeometry.openButtonRightInset, baseline.openButtonRightInset],
      ]
        .filter(([, actual, expected]) => Math.abs(actual - expected) > 0.6)
        .map(([label, actual, expected]) => `${label}: ${actual.toFixed(2)} vs ${expected.toFixed(2)}`);

      if (resetFailures.length) {
        throw new Error(`grid layout config reset drifted\n- ${resetFailures.join("\n- ")}`);
      }

      await page.click("#gridToggleSidebar");
      await page.waitForFunction(() => document.body.classList.contains("sidebar-open"), null, { timeout: 10000 });
      await waitForGridDrawerState(true);
      await page.click('[data-drawer-tab="settings"]');
      await page.waitForFunction(() => document.getElementById("drawerPanelSettings")?.classList.contains("is-active"), null, {
        timeout: 10000,
      });
    });

    await runStep("open-theme-palette", async () => {
      await page.click("#themePaletteButton");
      await page.waitForFunction(() => {
        const menu = document.getElementById("themePaletteOptions");
        return !!menu && !menu.hidden && menu.children.length > 0;
      }, null, { timeout: 10000 });
    });

    await runStep("switch-theme-light", async () => {
      await page.click("#linkedSurfaceModeLight");
      await page.waitForFunction(() => document.getElementById("linkedSurfaceModeToggle")?.dataset.mode === "light", null, {
        timeout: 10000,
      });
    });

    await runStep("switch-theme-dark", async () => {
      await page.click("#linkedSurfaceModeDark");
      await page.waitForFunction(() => document.getElementById("linkedSurfaceModeToggle")?.dataset.mode === "dark", null, {
        timeout: 10000,
      });
    });

    await runStep("expand-symbol-highlight", async () => {
      await page.click("#linkedSurfaceEditorTab");
      await page.waitForFunction(() => document.getElementById("linkedSurfaceEditorPanel")?.hidden === false, null, {
        timeout: 10000,
      });
      await page.click("#symbolHighlightDisclosure > summary");
      await page.waitForFunction(() => document.getElementById("symbolHighlightDisclosure")?.open === true, null, {
        timeout: 10000,
      });
      await page.waitForFunction(() => {
        const list = document.getElementById("glyphColorList");
        return !!list && list.children.length > 0;
      }, null, { timeout: 10000 });
      await page.click("#linkedSurfaceThemeTab");
      await page.waitForFunction(() => document.getElementById("linkedSurfaceThemePanel")?.hidden === false, null, {
        timeout: 10000,
      });
    });

    await runStep("linked-surface-tabs-defaults", async () => {
      await page.waitForSelector("#linkedSurfaceThemeTab", { timeout: 10000 });
      await page.waitForSelector("#linkedSurfaceEditorTab", { timeout: 10000 });
      await page.waitForSelector("#linkedSurfaceModeToggle", { timeout: 10000 });
      await page.waitForFunction(() => {
        const themeTab = document.getElementById("linkedSurfaceThemeTab");
        const editorTab = document.getElementById("linkedSurfaceEditorTab");
        const linkButton = document.getElementById("linkedEditorModeLinkButton");
        return (
          themeTab?.classList.contains("is-active") === true &&
          editorTab?.classList.contains("is-active") === false &&
          document.getElementById("linkedSurfaceThemePanel")?.hidden === false &&
          document.getElementById("linkedSurfaceEditorPanel")?.hidden === true &&
          linkButton?.hidden === true
        );
      }, null, { timeout: 10000 });
    });

    await runStep("linked-surface-editor-locked", async () => {
      await page.click("#linkedSurfaceEditorTab");
      await page.waitForFunction(() => {
        const linkButton = document.getElementById("linkedEditorModeLinkButton");
        const darkButton = document.getElementById("linkedSurfaceModeDark");
        const lightButton = document.getElementById("linkedSurfaceModeLight");
        return (
          linkButton?.hidden === false &&
          linkButton?.classList.contains("is-linked") === true &&
          darkButton?.disabled === true &&
          lightButton?.disabled === true
        );
      }, null, { timeout: 10000 });
    });

    await runStep("linked-surface-editor-unlocked", async () => {
      await page.click("#linkedEditorModeLinkButton");
      await page.waitForFunction(() => {
        const linkButton = document.getElementById("linkedEditorModeLinkButton");
        const darkButton = document.getElementById("linkedSurfaceModeDark");
        const lightButton = document.getElementById("linkedSurfaceModeLight");
        return (
          linkButton?.classList.contains("is-linked") === false &&
          darkButton?.disabled === false &&
          lightButton?.disabled === false
        );
      }, null, { timeout: 10000 });
      await page.click("#linkedSurfaceModeLight");
      await page.waitForFunction(() => document.getElementById("linkedSurfaceModeToggle")?.dataset.mode === "light", null, {
        timeout: 10000,
      });
      await page.click("#linkedEditorModeLinkButton");
      await page.waitForFunction(() => {
        const linkButton = document.getElementById("linkedEditorModeLinkButton");
        const toggle = document.getElementById("linkedSurfaceModeToggle");
        return linkButton?.classList.contains("is-linked") === true && toggle?.dataset.mode === "dark";
      }, null, { timeout: 10000 });
    });

    if (pageErrors.length || consoleErrors.length || requestFailures.length) {
      await ensureArtifactDir();
      await page.screenshot({ path: SCREENSHOT_PATH, fullPage: true });
      const detail = [
        pageErrors.length ? `page errors:\n- ${pageErrors.join("\n- ")}` : "",
        consoleErrors.length ? `console errors:\n- ${consoleErrors.join("\n- ")}` : "",
        requestFailures.length ? `request failures:\n- ${requestFailures.join("\n- ")}` : "",
      ]
        .filter(Boolean)
        .join("\n\n");
      throw new Error(`step ${currentStep} failed validation\n${detail}\nfailure screenshot: ${SCREENSHOT_PATH}`);
    }

    log("editor load self-test passed");
    if (consoleWarnings.length) {
      log(`warnings (${consoleWarnings.length}):`);
      for (const warning of consoleWarnings) {
        log(`- ${warning}`);
      }
    }
  } catch (error) {
    await ensureArtifactDir();
    await page.screenshot({ path: SCREENSHOT_PATH, fullPage: true }).catch(() => {});
    const detail = [
      pageErrors.length ? `page errors:\n- ${pageErrors.join("\n- ")}` : "",
      consoleErrors.length ? `console errors:\n- ${consoleErrors.join("\n- ")}` : "",
      requestFailures.length ? `request failures:\n- ${requestFailures.join("\n- ")}` : "",
    ]
      .filter(Boolean)
      .join("\n\n");
    throw new Error(
      [`step ${currentStep} failed`, error?.message ?? String(error), detail, `failure screenshot: ${SCREENSHOT_PATH}`]
        .filter(Boolean)
        .join("\n\n"),
    );
  } finally {
    await browser.close();
    if (server.started && server.child) {
      server.child.kill("SIGTERM");
    }
  }
}

runSelfTest().catch(async (error) => {
  fail(`editor load self-test failed: ${error?.message ?? error}`);
  process.exitCode = 1;
});
