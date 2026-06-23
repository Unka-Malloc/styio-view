const body = document.body;
const themeNames = ["oxide", "tide", "cinder"];
const themeLabels = { oxide: "Oxide", tide: "Tide", cinder: "Cinder" };
const workspaceApiBase = "/api/workspace";

const defaultSources = {
  "main.styio": `pipeline feed
let renderFlow = source |> normalize -> render
fn bootGraph(input) {
  state idle
  when input.ready -> state running
  spawn worker.alpha
  spawn worker.beta
}`,
  "render_flow.styio": `pipeline renderFlow
let commitFlow = source |> normalize |> shade -> commit
fn commitFrame(frame) {
  state paint_ready
  when frame.ready -> state submitted
  emit frame.commit
}`,
  "runtime_graph.styio": `pipeline monitor
fn stageGraph(session) {
  state idle
  when session.ready -> state running
  when session.joined -> state complete
}
state complete`,
  "mobile_profile.styio": `pipeline mobilePredict
fn mobilePredictor(input) {
  state waiting
  when input.stable -> state suggestion_ready
}
profile sync local_only`,
};

const fileSources = { ...defaultSources };
const fileDirtyState = {
  "main.styio": true,
  "render_flow.styio": false,
  "runtime_graph.styio": false,
  "mobile_profile.styio": false,
};

const moduleLabels = {
  localCompile: "local compile",
  graphRuntime: "graph runtime",
  cloudAgent: "cloud agent",
  localAgent: "local agent",
};

const platformProfiles = {
  macos: {
    label: "macOS desktop",
    mode: "desktop",
    blocked: [],
    required: [],
    policy:
      "macOS desktop keeps local compile available and can mount the local agent bridge on demand.",
    workspacePrefix: "workspace: local-first / macOS profile / focused ",
    runtimeLabel: "runtime: macOS desktop profile loaded / local compile available",
  },
  android: {
    label: "Android mobile",
    mode: "mobile",
    blocked: [],
    required: [],
    policy:
      "Android keeps the shared core but can choose between local compile and cloud fallback under the 50 MB runtime budget.",
    workspacePrefix: "workspace: local-first / Android profile / focused ",
    runtimeLabel: "runtime: Android mobile profile loaded / local compile optional",
  },
  ios: {
    label: "iOS client",
    mode: "mobile",
    blocked: ["localCompile", "localAgent"],
    required: ["cloudAgent"],
    policy:
      "iOS only exposes the cloud-safe execution path. Local compile and local agent bridge stay unmounted for store-safe distribution.",
    workspacePrefix: "workspace: cloud-connected / iOS profile / focused ",
    runtimeLabel: "runtime: iOS cloud-safe profile loaded / local compile hidden",
  },
  web: {
    label: "Hosted web",
    mode: "desktop",
    blocked: ["localCompile", "localAgent"],
    required: ["cloudAgent"],
    policy:
      "Hosted web runs through cloud workspace sessions, keeps export and retention flows, and does not mount local compile.",
    workspacePrefix: "workspace: hosted / web profile / focused ",
    runtimeLabel: "runtime: hosted web profile loaded / export + retention gate active",
  },
};

const platformModuleState = {
  macos: {
    localCompile: true,
    graphRuntime: true,
    cloudAgent: true,
    localAgent: false,
  },
  android: {
    localCompile: true,
    graphRuntime: true,
    cloudAgent: true,
    localAgent: false,
  },
  ios: {
    localCompile: false,
    graphRuntime: true,
    cloudAgent: true,
    localAgent: false,
  },
  web: {
    localCompile: false,
    graphRuntime: true,
    cloudAgent: true,
    localAgent: false,
  },
};

let themeIndex = 0;
let substitutionOn = true;
let activePlatform = "macos";
let currentFile = "main.styio";
let restartQueued = false;
let restartBannerDismissed = false;
let currentAnalysis = null;
let workspaceApiAvailable = false;
let saveInFlight = false;

const substitutionButton = document.getElementById("toggleSubstitution");
const saveFileAction = document.getElementById("saveFileAction");
const themeButton = document.getElementById("cycleTheme");
const runtimeButton = document.getElementById("runUnit");
const stagedButton = document.getElementById("applyStagedUpdate");
const runtimeStatus = document.getElementById("runtimeStatus");
const statusRuntime = document.getElementById("statusRuntime");
const statusWorkspace = document.getElementById("statusWorkspace");
const statusRetention = document.getElementById("statusRetention");
const updateState = document.getElementById("updateState");
const updateCard = document.getElementById("updateCard");
const eventConsole = document.getElementById("eventConsole");
const providerCard = document.getElementById("providerCard");
const runtimeEntryGroup = document.getElementById("runtimeEntryGroup");
const diagnosticMeta = document.getElementById("diagnosticMeta");
const selectionMeta = document.getElementById("selectionMeta");
const projectionMeta = document.getElementById("projectionMeta");
const currentFileChip = document.getElementById("currentFileChip");
const sourceModeChip = document.getElementById("sourceModeChip");
const blockModeChip = document.getElementById("blockModeChip");
const renderStatChip = document.getElementById("renderStatChip");
const saveStateChip = document.getElementById("saveStateChip");
const bufferStateChip = document.getElementById("bufferStateChip");
const bufferLineStat = document.getElementById("bufferLineStat");
const symbolStat = document.getElementById("symbolStat");
const blockStat = document.getElementById("blockStat");
const compileUnitStat = document.getElementById("compileUnitStat");
const sourceBuffer = document.getElementById("sourceBuffer");
const sourceLineGutter = document.getElementById("sourceLineGutter");
const renderSurface = document.getElementById("renderSurface");
const patchState = document.getElementById("patchState");
const patchDiff = document.getElementById("patchDiff");
const dialog = document.getElementById("workspaceDialog");
const deadlineNode = document.getElementById("workspaceDeadline");
const restartBanner = document.getElementById("restartBanner");
const restartBannerText = document.getElementById("restartBannerText");
const platformRuntimeTag = document.getElementById("platformRuntimeTag");
const platformPolicyText = document.getElementById("platformPolicyText");
const debugAdaptersText = document.getElementById("debugAdaptersText");
const graphSurface = document.querySelector(".graph-surface");
const diagPrimaryTitle = document.getElementById("diagPrimaryTitle");
const diagPrimaryBody = document.getElementById("diagPrimaryBody");
const diagSecondaryTitle = document.getElementById("diagSecondaryTitle");
const diagSecondaryBody = document.getElementById("diagSecondaryBody");
const diagTertiaryTitle = document.getElementById("diagTertiaryTitle");
const diagTertiaryBody = document.getElementById("diagTertiaryBody");
const symbolPrimaryName = document.getElementById("symbolPrimaryName");
const symbolPrimaryMeta = document.getElementById("symbolPrimaryMeta");
const symbolSecondaryName = document.getElementById("symbolSecondaryName");
const symbolSecondaryMeta = document.getElementById("symbolSecondaryMeta");
const symbolTertiaryName = document.getElementById("symbolTertiaryName");
const symbolTertiaryMeta = document.getElementById("symbolTertiaryMeta");

const nextWeek = new Date();
nextWeek.setDate(nextWeek.getDate() + 7);
deadlineNode.textContent = nextWeek.toLocaleDateString("zh-CN");

function escapeHtml(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function countMatches(value, regex) {
  return (value.match(regex) || []).length;
}

function countChar(value, char) {
  return countMatches(value, new RegExp(`\\${char}`, "g"));
}

function padLine(index) {
  return String(index + 1).padStart(2, "0");
}

function getProfile() {
  return platformProfiles[activePlatform];
}

function getModules() {
  const profile = getProfile();
  const state = platformModuleState[activePlatform];

  profile.blocked.forEach((moduleId) => {
    state[moduleId] = false;
  });

  profile.required.forEach((moduleId) => {
    state[moduleId] = true;
  });

  return state;
}

function setMode(mode) {
  document.querySelectorAll("[data-mode]").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.mode === mode);
  });

  body.classList.toggle("mode-mobile", mode === "mobile");
  body.classList.toggle("mode-desktop", mode === "desktop");
}

function getLines(source) {
  return source.replace(/\r\n/g, "\n").split("\n");
}

function findSemanticBlocks(lines) {
  const blocks = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];

    if (!/^\s*fn\s+/.test(line) || !line.includes("{")) {
      continue;
    }

    let depth = countChar(line, "{") - countChar(line, "}");

    if (depth <= 0) {
      continue;
    }

    let cursor = index + 1;

    while (cursor < lines.length && depth > 0) {
      depth += countChar(lines[cursor], "{") - countChar(lines[cursor], "}");
      if (depth === 0) {
        break;
      }
      cursor += 1;
    }

    if (cursor < lines.length && depth === 0) {
      const match = line.match(/^\s*fn\s+([A-Za-z_]\w*)/);
      blocks.push({
        header: index,
        innerStart: index + 1,
        innerEnd: Math.max(index, cursor - 1),
        closing: cursor,
        title: match ? match[1] : "anonymous",
      });
      index = cursor;
    }
  }

  return blocks;
}

function analyzeSource(source) {
  const lines = getLines(source);
  const arrowCount = countMatches(source, /->/g);
  const pipeCount = countMatches(source, /\|>/g);
  const renderCandidates = arrowCount + pipeCount;
  const braceBalance = countMatches(source, /{/g) - countMatches(source, /}/g);
  const blocks = findSemanticBlocks(lines);
  const pipelineMatch = source.match(/^\s*pipeline\s+([A-Za-z_]\w*)/m);
  const fnMatch = source.match(/^\s*fn\s+([A-Za-z_]\w*)/m);
  const stateMatch = source.match(/^\s*state\s+([A-Za-z_]\w*)/m);
  const warnings = [];
  const errors = [];

  const betaIndex = lines.findIndex((line) => line.includes("spawn worker.beta"));
  if (betaIndex !== -1 && !source.includes("joined(")) {
    warnings.push({
      lineIndex: betaIndex,
      title: `line ${padLine(betaIndex)} / parallel worker`,
      body: "worker.beta is present, but no explicit join strategy is declared for the render path.",
    });
  }

  if (braceBalance !== 0) {
    const headerIndex = lines.findIndex((line) => /^\s*fn\s+/.test(line));
    errors.push({
      lineIndex: headerIndex === -1 ? 0 : headerIndex,
      title: "brace balance / compile blocked",
      body: "semantic block boundaries are incomplete, so the minimal compilable unit cannot be closed yet.",
    });
  }

  const primaryFunctionLine = lines.findIndex((line) => /^\s*fn\s+/.test(line));
  const selectedLineIndex =
    (errors[0] && errors[0].lineIndex) ??
    (warnings[0] && warnings[0].lineIndex) ??
    (primaryFunctionLine === -1 ? 0 : Math.min(primaryFunctionLine + 1, lines.length - 1));

  const ready = Boolean(fnMatch) && braceBalance === 0;

  return {
    lines,
    arrowCount,
    pipeCount,
    renderCandidates,
    transitionCount: arrowCount,
    braceBalance,
    blocks,
    blockCount: blocks.length,
    pipelineName: pipelineMatch ? pipelineMatch[1] : null,
    functionName: fnMatch ? fnMatch[1] : null,
    stateName: stateMatch ? stateMatch[1] : null,
    warnings,
    errors,
    ready,
    selectedLineIndex,
    symbolSummary: {
      primaryName: pipelineMatch ? `pipeline ${pipelineMatch[1]}` : "pipeline missing",
      primaryMeta: pipelineMatch
        ? `${renderCandidates} glyph candidates / ${pipeCount} pipeline hops`
        : "declare a pipeline to unlock inline flow previews",
      secondaryName: fnMatch ? `fn ${fnMatch[1]}` : "function missing",
      secondaryMeta: fnMatch
        ? `${blocks.length} semantic block / ${lines.length} source lines`
        : "minimal unit not formed yet",
      tertiaryName: stateMatch ? `state ${stateMatch[1]}` : "state missing",
      tertiaryMeta: stateMatch
        ? `${arrowCount} transition glyphs / ${warnings.length} warnings`
        : "state surface appears after control flow declarations",
    },
  };
}

function renderTokenMarkup(text) {
  let output = escapeHtml(text);
  output = output.replace(/\|&gt;/g, `
    <span class="token token-pipe" data-raw="|>">
      <span class="token-visual"></span>
      <span class="token-raw">|&gt;</span>
    </span>
  `);
  output = output.replace(/-&gt;/g, `
    <span class="token token-arrow" data-raw="->">
      <span class="token-visual"></span>
      <span class="token-raw">-&gt;</span>
    </span>
  `);
  return output;
}

function renderLine(line, index, options = {}) {
  const classes = ["code-line"];

  if (options.selected) {
    classes.push("is-selected");
  }

  if (options.diagnostic) {
    classes.push("has-diagnostic");
  }

  return `
    <div class="${classes.join(" ")}">
      <span class="line-no">${padLine(index)}</span>
      <span class="code-text">${renderTokenMarkup(line)}</span>
    </div>
  `;
}

function buildRenderProjection(analysis) {
  const blockMap = new Map(analysis.blocks.map((block) => [block.header, block]));
  const issueLines = new Set([
    ...analysis.warnings.map((entry) => entry.lineIndex),
    ...analysis.errors.map((entry) => entry.lineIndex),
  ]);

  let html = "";

  for (let index = 0; index < analysis.lines.length; index += 1) {
    const block = blockMap.get(index);

    if (block) {
      html += renderLine(analysis.lines[index], index, {
        selected: analysis.selectedLineIndex === index,
        diagnostic: issueLines.has(index),
      });

      html += `
        <div class="semantic-block">
          <div class="semantic-caption">semantic block surface / fn ${escapeHtml(block.title)}</div>
      `;

      for (let cursor = block.innerStart; cursor <= block.innerEnd; cursor += 1) {
        html += renderLine(analysis.lines[cursor], cursor, {
          selected: analysis.selectedLineIndex === cursor,
          diagnostic: issueLines.has(cursor),
        });
      }

      html += "</div>";

      if (block.closing < analysis.lines.length) {
        html += renderLine(analysis.lines[block.closing], block.closing, {
          selected: analysis.selectedLineIndex === block.closing,
          diagnostic: issueLines.has(block.closing),
        });
      }

      index = block.closing;
      continue;
    }

    html += renderLine(analysis.lines[index], index, {
      selected: analysis.selectedLineIndex === index,
      diagnostic: issueLines.has(index),
    });
  }

  renderSurface.innerHTML = html;
}

function renderLineGutter(lines) {
  sourceLineGutter.innerHTML = lines
    .map((_, index) => `<span>${padLine(index)}</span>`)
    .join("");
}

function setSaveVisualState(kind, detail) {
  saveStateChip.textContent = detail;
  bufferStateChip.textContent = detail;
  saveStateChip.dataset.saveState = kind;
  bufferStateChip.dataset.saveState = kind;
}

function updateSaveUI() {
  const dirty = Boolean(fileDirtyState[currentFile]);

  saveFileAction.textContent = saveInFlight ? "Saving..." : "Save";
  saveFileAction.disabled = saveInFlight;

  if (!workspaceApiAvailable) {
    setSaveVisualState("volatile", "disk: api offline");
    return;
  }

  if (saveInFlight) {
    setSaveVisualState("saving", "disk: saving");
    return;
  }

  if (dirty) {
    setSaveVisualState("dirty", "disk: unsaved edits");
    return;
  }

  setSaveVisualState("saved", `disk: saved / workspace/${currentFile}`);
}

function updateTabStates() {
  document.querySelectorAll("[data-open-file]").forEach((button) => {
    const fileName = button.dataset.openFile;
    const analysis = analyzeSource(fileSources[fileName]);
    const tabState = button.querySelector(".tab-state");

    tabState.className = "tab-state";

    if (fileDirtyState[fileName]) {
      tabState.textContent = "dirty";
      tabState.classList.add("dirty");
      return;
    }

    const totalIssues = analysis.warnings.length + analysis.errors.length;

    if (totalIssues > 0) {
      tabState.textContent = String(totalIssues);
      tabState.classList.add("warn");
      return;
    }

    if (fileName === "mobile_profile.styio") {
      tabState.textContent = "sync";
      return;
    }

    tabState.textContent = "saved";
  });
}

function updateSymbolCards(analysis) {
  symbolPrimaryName.textContent = analysis.symbolSummary.primaryName;
  symbolPrimaryMeta.textContent = analysis.symbolSummary.primaryMeta;
  symbolSecondaryName.textContent = analysis.symbolSummary.secondaryName;
  symbolSecondaryMeta.textContent = analysis.symbolSummary.secondaryMeta;
  symbolTertiaryName.textContent = analysis.symbolSummary.tertiaryName;
  symbolTertiaryMeta.textContent = analysis.symbolSummary.tertiaryMeta;
}

function updateDiagnosticRail(analysis) {
  const primary = analysis.errors[0] || analysis.warnings[0] || {
    title: `line ${padLine(analysis.selectedLineIndex)} / symbol projection`,
    body: "symbol projection is stable and no blocking compile issue is present in the active unit.",
  };

  diagPrimaryTitle.textContent = primary.title;
  diagPrimaryBody.textContent = primary.body;

  diagSecondaryTitle.textContent = `symbol render / ${analysis.renderCandidates} candidates`;
  diagSecondaryBody.textContent = substitutionOn
    ? "`->` renders as an arrow glyph and `|>` renders as a triangular pipeline glyph in projection mode."
    : "substitution is disabled, so the projection keeps raw source tokens visible while preserving layout analysis.";

  diagTertiaryTitle.textContent = `semantic blocks / ${analysis.blockCount}`;
  diagTertiaryBody.textContent = analysis.ready
    ? "current minimal unit is compilable and can flow into save-triggered compile or Ctrl+Enter execution."
    : "current source is not yet a closed minimal unit, so execution will stop at compile validation.";
}

function renderWorkspaceStatus() {
  statusWorkspace.textContent = `${getProfile().workspacePrefix}${currentFile}`;
}

function renderDiagnostics(analysis) {
  currentAnalysis = analysis;
  currentFileChip.textContent = currentFile;
  diagnosticMeta.textContent = `${analysis.warnings.length} warning / ${analysis.errors.length} errors`;
  selectionMeta.textContent = analysis.functionName
    ? `fn ${analysis.functionName} / line ${padLine(analysis.selectedLineIndex)} / ${analysis.lines.length} lines`
    : `${currentFile} / ${analysis.lines.length} lines / no function surface`;
  projectionMeta.textContent = `${analysis.renderCandidates} glyph candidates / ${analysis.blockCount} semantic blocks / ${analysis.ready ? "compile ready" : "compile incomplete"}`;
  sourceModeChip.textContent = workspaceApiAvailable
    ? "source fidelity locked / disk-backed"
    : "source fidelity locked / memory fallback";
  blockModeChip.textContent = analysis.blockCount > 0 ? `${analysis.blockCount} block surface active` : "block surface pending";
  renderStatChip.textContent = `${analysis.renderCandidates} symbol renders / ${analysis.pipeCount} pipeline hops`;
  bufferLineStat.textContent = `${analysis.lines.length} lines`;
  symbolStat.textContent = `${analysis.renderCandidates} glyph candidates`;
  blockStat.textContent = `${analysis.blockCount} semantic blocks`;
  compileUnitStat.textContent = analysis.ready ? "minimal unit ready" : "minimal unit incomplete";
  updateSymbolCards(analysis);
  updateDiagnosticRail(analysis);
}

function renderEditorSurface() {
  const source = fileSources[currentFile];
  const analysis = analyzeSource(source);
  renderLineGutter(analysis.lines);
  buildRenderProjection(analysis);
  renderDiagnostics(analysis);
  updateTabStates();
  updateSaveUI();
}

function focusFile(fileName) {
  currentFile = fileName;

  document.querySelectorAll("[data-file]").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.file === fileName);
  });

  document.querySelectorAll("[data-open-file]").forEach((item) => {
    item.classList.toggle("is-active", item.dataset.openFile === fileName);
  });

  sourceBuffer.value = fileSources[currentFile];
  sourceBuffer.scrollTop = 0;
  sourceLineGutter.scrollTop = 0;
  renderSurface.scrollTop = 0;

  renderWorkspaceStatus();
  renderEditorSurface();
}

function renderProviderState(modules) {
  const cloudText = modules.cloudAgent ? "cloud adapter active" : "cloud adapter absent";
  const localText = modules.localAgent ? "local bridge mounted" : "local bridge absent";
  providerCard.querySelector(".prompt-text").textContent =
    `${cloudText} / ${localText} / profile sync local-only`;
}

function renderDebugAdapters(modules) {
  const parts = [
    modules.graphRuntime ? "graphRuntime mounted" : "graphRuntime absent",
    modules.cloudAgent ? "cloudAgent mounted" : "cloudAgent absent",
    modules.localAgent ? "localAgent mounted" : "localAgent absent",
  ];

  if (modules.localCompile) {
    parts.push("localCompile mounted");
  } else if (getProfile().blocked.includes("localCompile")) {
    parts.push("localCompile blocked");
  } else {
    parts.push("localCompile unmounted");
  }

  debugAdaptersText.textContent = parts.join(" / ");
}

function renderGraphSurface(modules) {
  if (modules.graphRuntime) {
    graphSurface.innerHTML = `
      <div class="graph-node active">idle</div>
      <div class="graph-link"></div>
      <div class="graph-node">running</div>
      <div class="graph-link"></div>
      <div class="graph-node ghost">join</div>
    `;
    return;
  }

  graphSurface.innerHTML = `
    <div class="graph-fallback">
      graph runtime is unmounted for this platform profile. console fallback stays active until the module returns.
    </div>
  `;
}

function syncRestartBanner() {
  const modules = getModules();
  const platformLabel = getProfile().label;
  platformRuntimeTag.textContent = `platform: ${platformLabel}`;
  restartBannerText.textContent = modules.graphRuntime
    ? `${platformLabel} keeps the current graph runtime alive until restart. after relaunch, the staged graphRuntime package replaces the mounted entry.`
    : `${platformLabel} has no graph runtime mounted right now. restart will still attach the staged graphRuntime package.`;
  restartBanner.hidden = !restartQueued || restartBannerDismissed;
  updateState.textContent = restartQueued ? "queued for restart" : "staged";
  stagedButton.textContent = restartQueued ? "Restart queued" : "Staged: 1";
  updateCard.classList.toggle("is-highlight", restartQueued);
}

function syncPlatformSurface() {
  const profile = getProfile();
  const modules = getModules();

  document.querySelectorAll("[data-platform]").forEach((card) => {
    card.classList.toggle("is-active", card.dataset.platform === activePlatform);
  });

  platformPolicyText.textContent = profile.policy;
  statusRuntime.textContent = profile.runtimeLabel;
  renderWorkspaceStatus();
  renderProviderState(modules);
  renderDebugAdapters(modules);
  renderGraphSurface(modules);
  syncRestartBanner();

  if (!modules.graphRuntime) {
    runtimeStatus.textContent = "graph runtime unavailable / console fallback only";
  }
}

function syncModuleUI() {
  const profile = getProfile();
  const modules = getModules();

  Object.keys(moduleLabels).forEach((moduleId) => {
    const installed = modules[moduleId];
    const blocked = profile.blocked.includes(moduleId);
    const required = profile.required.includes(moduleId);
    const pill = document.querySelector(`.module-pill[data-module="${moduleId}"]`);
    const libraryCard = document.querySelector(`[data-library-card="${moduleId}"]`);
    const libraryState = document.querySelector(`[data-library-state="${moduleId}"]`);
    const libraryAction = document.querySelector(`[data-library-action="${moduleId}"]`);
    const registryCard = document.querySelector(`[data-card="${moduleId}"]`);

    pill.classList.toggle("is-installed", installed);
    pill.classList.toggle("is-blocked", blocked);
    pill.disabled = blocked;
    pill.title = blocked ? `${moduleLabels[moduleId]} is blocked on ${profile.label}` : "";

    if (registryCard) {
      registryCard.classList.toggle("is-muted", !installed);
      const registryState = registryCard.querySelector(".registry-state");
      registryState.textContent = blocked ? "blocked" : required ? "required" : installed ? "mounted" : "not installed";
    }

    if (libraryCard && libraryState && libraryAction) {
      libraryCard.classList.toggle("is-muted", !installed);
      libraryState.textContent = blocked ? "blocked" : required ? "required" : installed ? "mounted" : "not installed";
      libraryAction.textContent = blocked ? "Blocked" : required ? "Required" : installed ? "Unmount" : "Install";
      libraryAction.classList.toggle("is-disabled", blocked || required);
      libraryAction.disabled = blocked || required;
    }
  });

  runtimeEntryGroup.style.opacity = modules.graphRuntime ? "1" : "0.45";
}

function syncAll() {
  setMode(getProfile().mode);
  renderEditorSurface();
  syncModuleUI();
  syncPlatformSurface();
}

function toggleModule(moduleId) {
  const profile = getProfile();

  if (profile.blocked.includes(moduleId) || profile.required.includes(moduleId)) {
    runtimeStatus.textContent = `${moduleLabels[moduleId]} cannot change on ${profile.label}`;
    return;
  }

  const modules = getModules();
  modules[moduleId] = !modules[moduleId];
  syncModuleUI();
  syncPlatformSurface();

  if (moduleId === "graphRuntime") {
    runtimeStatus.textContent = modules[moduleId]
      ? "graph runtime registry restored"
      : "graph runtime removed / console fallback only";
  }

  if (moduleId === "localCompile") {
    statusRuntime.textContent = modules[moduleId]
      ? `${getProfile().runtimeLabel}`
      : `${getProfile().runtimeLabel.replace("local compile available", "cloud fallback active").replace("local compile optional", "cloud fallback active")}`;
  }
}

async function saveCurrentFile() {
  if (saveInFlight) {
    return;
  }

  if (!workspaceApiAvailable) {
    runtimeStatus.textContent = "save unavailable / workspace api offline";
    updateSaveUI();
    return;
  }

  saveInFlight = true;
  updateSaveUI();

  try {
    const response = await fetch(`${workspaceApiBase}/${encodeURIComponent(currentFile)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: sourceBuffer.value }),
    });

    if (!response.ok) {
      throw new Error(`save failed with ${response.status}`);
    }

    const payload = await response.json();
    fileSources[currentFile] = sourceBuffer.value;
    fileDirtyState[currentFile] = false;
    renderEditorSurface();
    runtimeStatus.textContent = `saved ${payload.file} to disk`;
    statusRuntime.textContent = `${getProfile().runtimeLabel} / last save ${payload.bytes} bytes`;
  } catch (error) {
    console.error(error);
    setSaveVisualState("error", "disk: save failed");
    runtimeStatus.textContent = "save failed / check local dev server";
    return;
  } finally {
    saveInFlight = false;
    updateSaveUI();
  }
}

async function loadWorkspaceFromDisk() {
  try {
    const response = await fetch(workspaceApiBase, { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`load failed with ${response.status}`);
    }

    const payload = await response.json();
    const files = payload.files || {};

    Object.entries(files).forEach(([fileName, content]) => {
      if (typeof content === "string") {
        fileSources[fileName] = content;
        fileDirtyState[fileName] = false;
      }
    });

    workspaceApiAvailable = true;
    focusFile(currentFile);
    statusRuntime.textContent = `${getProfile().runtimeLabel} / workspace files loaded from disk`;
    runtimeStatus.textContent = "workspace hydrated from local disk";
  } catch (error) {
    console.error(error);
    workspaceApiAvailable = false;
    renderEditorSurface();
    runtimeStatus.textContent = "workspace api unavailable / memory-only fallback";
  } finally {
    updateSaveUI();
  }
}

document.querySelectorAll("[data-mode]").forEach((button) => {
  button.addEventListener("click", () => {
    setMode(button.dataset.mode);
    statusRuntime.textContent =
      button.dataset.mode === "mobile"
        ? `runtime: ${getProfile().label} / vertical shell preview`
        : `runtime: ${getProfile().label} / dense desktop shell preview`;
  });
});

document.querySelectorAll("[data-platform]").forEach((card) => {
  card.addEventListener("click", () => {
    activePlatform = card.dataset.platform;
    syncAll();
    runtimeStatus.textContent = `${getProfile().label} capability profile loaded`;
  });
});

document.querySelectorAll("[data-file]").forEach((button) => {
  button.addEventListener("click", () => {
    focusFile(button.dataset.file);
  });
});

document.querySelectorAll("[data-open-file]").forEach((button) => {
  button.addEventListener("click", () => {
    focusFile(button.dataset.openFile);
  });
});

sourceBuffer.addEventListener("input", () => {
  fileSources[currentFile] = sourceBuffer.value;
  fileDirtyState[currentFile] = true;
  renderEditorSurface();
  runtimeStatus.textContent = `source buffer updated / render projection refreshed for ${currentFile}`;
});

sourceBuffer.addEventListener("scroll", () => {
  sourceLineGutter.scrollTop = sourceBuffer.scrollTop;
  renderSurface.scrollTop = sourceBuffer.scrollTop;
});

substitutionButton.addEventListener("click", () => {
  substitutionOn = !substitutionOn;
  body.classList.toggle("substitution-off", !substitutionOn);
  substitutionButton.textContent = `Substitution: ${substitutionOn ? "On" : "Off"}`;
  renderEditorSurface();
});

saveFileAction.addEventListener("click", () => {
  saveCurrentFile();
});

themeButton.addEventListener("click", () => {
  body.classList.remove(`theme-${themeNames[themeIndex]}`);
  themeIndex = (themeIndex + 1) % themeNames.length;
  body.classList.add(`theme-${themeNames[themeIndex]}`);
  themeButton.textContent = `Theme: ${themeLabels[themeNames[themeIndex]]}`;
});

document.querySelectorAll("[data-runtime-tab]").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll("[data-runtime-tab]").forEach((item) => item.classList.remove("is-active"));
    document.querySelectorAll(".runtime-tab-panel").forEach((item) => item.classList.remove("is-active"));
    button.classList.add("is-active");

    const tab = button.dataset.runtimeTab;
    body.classList.remove("runtime-graph", "runtime-console", "runtime-debug");
    body.classList.add(`runtime-${tab}`);
    document.getElementById(`runtimePanel${tab.charAt(0).toUpperCase()}${tab.slice(1)}`).classList.add("is-active");
    runtimeStatus.textContent = `runtime tab: ${tab}`;
  });
});

runtimeButton.addEventListener("click", () => {
  const modules = getModules();
  const analysis = analyzeSource(fileSources[currentFile]);

  if (!analysis.ready) {
    runtimeStatus.textContent = "compile blocked / minimal unit incomplete";
    eventConsole.innerHTML = `
      <div class="console-line"><span>005</span><span>compile.blocked / ${currentFile} / semantic block not closed</span></div>
      <div class="console-line"><span>006</span><span>diagnostic.emitted / brace balance or function surface incomplete</span></div>
    `;
    return;
  }

  const executionOrigin = modules.localCompile ? "local compile" : "cloud delegate";

  if (modules.graphRuntime) {
    runtimeStatus.textContent = `${executionOrigin} -> thread.spawned -> transition.fired`;
    graphSurface.innerHTML = `
      <div class="graph-node">idle</div>
      <div class="graph-link"></div>
      <div class="graph-node active">running</div>
      <div class="graph-link"></div>
      <div class="graph-node ghost">join</div>
    `;
  } else {
    runtimeStatus.textContent = `${executionOrigin} -> console fallback / graph runtime absent`;
  }

  statusRuntime.textContent = `runtime: active run session / ${executionOrigin} / ${getProfile().label}`;
  eventConsole.innerHTML = `
    <div class="console-line"><span>005</span><span>compile.started / ${executionOrigin} / unit ${currentFile}</span></div>
    <div class="console-line"><span>006</span><span>run.started / session-${analysis.functionName || "unit"}</span></div>
    <div class="console-line"><span>007</span><span>thread.spawned / alpha</span></div>
    <div class="console-line"><span>008</span><span>thread.spawned / beta</span></div>
    <div class="console-line"><span>009</span><span>transition.fired / ${analysis.stateName || "idle"} -> running</span></div>
    <div class="console-line"><span>010</span><span>projection.rendered / ${analysis.renderCandidates} glyph candidates</span></div>
  `;

  window.clearTimeout(runtimeButton._timer);
  runtimeButton._timer = window.setTimeout(() => {
    runtimeStatus.textContent = modules.graphRuntime
      ? "run.finished / graph surface updated"
      : "run.finished / console fallback remained active";
    statusRuntime.textContent = `${getProfile().runtimeLabel}`;
    renderGraphSurface(getModules());
  }, 1400);
});

stagedButton.addEventListener("click", () => {
  restartQueued = !restartQueued;
  restartBannerDismissed = false;
  syncRestartBanner();
  runtimeStatus.textContent = restartQueued
    ? "restart required / new graphRuntime will mount next session"
    : "staged update retained / old module still serving";
});

document.getElementById("dismissRestartBanner").addEventListener("click", () => {
  restartBannerDismissed = true;
  syncRestartBanner();
  runtimeStatus.textContent = "current session retained / restart reminder dismissed";
});

document.querySelectorAll(".module-pill").forEach((pill) => {
  pill.addEventListener("click", () => {
    toggleModule(pill.dataset.module);
  });
});

document.querySelectorAll(".library-action").forEach((button) => {
  button.addEventListener("click", () => {
    toggleModule(button.dataset.libraryAction);
  });
});

document.getElementById("previewPatch").addEventListener("click", () => {
  patchState.textContent = "preview";
  patchDiff.innerHTML = `
    <div class="diff-line remove">- spawn worker.beta</div>
    <div class="diff-line add">+ spawn worker.beta.joined("renderFlow")</div>
    <div class="diff-line add">+ state join_wait</div>
    <div class="diff-line add">+ when join_wait.complete -> state render_commit</div>
  `;
});

document.getElementById("inspectPatch").addEventListener("click", () => {
  patchState.textContent = "inspect";
  runtimeStatus.textContent = "agent patch inspected / source buffer unchanged";
});

document.getElementById("applyPatchAction").addEventListener("click", () => {
  patchState.textContent = "applied-preview";
  selectionMeta.textContent = `${currentFile} / patch preview applied to suggestion queue`;
  runtimeStatus.textContent = "agent patch moved to suggestion queue / not yet written to source buffer";
});

document.getElementById("closeWorkspace").addEventListener("click", () => dialog.showModal());
document.getElementById("cancelWorkspaceClose").addEventListener("click", () => dialog.close());
document.getElementById("confirmWorkspaceClose").addEventListener("click", () => {
  dialog.close();
  statusRetention.textContent = `retention: pending deletion until ${deadlineNode.textContent}`;
  runtimeStatus.textContent = "workspace pending deletion / export link retained 7 days";
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    saveCurrentFile();
    return;
  }

  if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
    event.preventDefault();
    runtimeButton.click();
  }
});

window.addEventListener("beforeunload", (event) => {
  if (!Object.values(fileDirtyState).some(Boolean)) {
    return;
  }

  event.preventDefault();
  event.returnValue = "";
});

async function bootstrap() {
  focusFile(currentFile);
  syncAll();
  await loadWorkspaceFromDisk();
}

bootstrap();
