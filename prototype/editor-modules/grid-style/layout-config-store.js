import { applyGridLayoutConfig } from "./layout-manager.js";

// Grid owns one layout config store for the whole page so spacing updates fan out from one source.
export const defaultGridLayoutConfig = Object.freeze({
  shell_inline_inset_base: 18,
  shell_vertical_inset_base: 16,
  inner_outer_margin_consistent: true,
  inner_margin: 1,
  outer_margin: 1,
});

export const gridLayoutConfigStore = createGridLayoutConfigStore(defaultGridLayoutConfig);

export function bindGridLayoutConfigTarget(target, { onAfterApply, emitCurrent = true } = {}) {
  return gridLayoutConfigStore.subscribe(
    (config) => {
      const applied = applyGridLayoutConfig(target, config);
      onAfterApply?.({
        config,
        applied,
      });
    },
    { emitCurrent },
  );
}

export function installGridLayoutConfigDebugApi(globalObject) {
  if (!globalObject) {
    return null;
  }

  const debugApi = Object.freeze({
    getSnapshot: () => gridLayoutConfigStore.getSnapshot(),
    set: (nextConfig) => gridLayoutConfigStore.set(nextConfig),
    update: (partialConfig) => gridLayoutConfigStore.update(partialConfig),
    reset: () => gridLayoutConfigStore.reset(),
  });

  globalObject.__vityoGridLayoutConfig = debugApi;
  return debugApi;
}

function createGridLayoutConfigStore(initialConfig) {
  let snapshot = normalizeGridLayoutConfig(initialConfig);
  const listeners = new Set();

  function notify() {
    listeners.forEach((listener) => {
      listener(snapshot);
    });
  }

  return Object.freeze({
    getSnapshot() {
      return snapshot;
    },
    set(nextConfig) {
      snapshot = normalizeGridLayoutConfig(nextConfig);
      notify();
      return snapshot;
    },
    update(partialConfig) {
      snapshot = normalizeGridLayoutConfig({
        ...snapshot,
        ...partialConfig,
      });
      notify();
      return snapshot;
    },
    reset() {
      snapshot = normalizeGridLayoutConfig(defaultGridLayoutConfig);
      notify();
      return snapshot;
    },
    subscribe(listener, { emitCurrent = true } = {}) {
      if (typeof listener !== "function") {
        return () => {};
      }

      listeners.add(listener);
      if (emitCurrent) {
        listener(snapshot);
      }
      return () => {
        listeners.delete(listener);
      };
    },
  });
}

function normalizeGridLayoutConfig(config = {}) {
  return Object.freeze({
    shell_inline_inset_base: normalizePositiveScalar(config.shell_inline_inset_base, defaultGridLayoutConfig.shell_inline_inset_base),
    shell_vertical_inset_base: normalizePositiveScalar(
      config.shell_vertical_inset_base,
      defaultGridLayoutConfig.shell_vertical_inset_base,
    ),
    inner_outer_margin_consistent:
      config.inner_outer_margin_consistent ?? defaultGridLayoutConfig.inner_outer_margin_consistent,
    inner_margin: normalizePositiveScalar(config.inner_margin, defaultGridLayoutConfig.inner_margin),
    outer_margin: normalizePositiveScalar(config.outer_margin, defaultGridLayoutConfig.outer_margin),
  });
}

function normalizePositiveScalar(value, fallback) {
  const numeric = Number(value);
  return Number.isFinite(numeric) && numeric > 0 ? numeric : fallback;
}
