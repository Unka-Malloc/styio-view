#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "..");
const manifestPath = path.join(root, "prototype-manifest.json");
const governancePath = path.join(root, "PROTOTYPE-GOVERNANCE.md");
const allowedStatuses = new Set(["canonical", "style-experiment"]);
const allowedOwners = new Set(["Shell / Editor", "Theme / UX"]);

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`${path.relative(root, filePath)} is not valid JSON: ${error.message}`);
  }
}

function listTopLevelHtml() {
  return fs
    .readdirSync(root, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".html"))
    .map((entry) => entry.name)
    .sort();
}

function hasMetadata(text) {
  return (
    /^#\s+.+/m.test(text) &&
    /^\*\*Purpose:\*\*\s+.+/m.test(text) &&
    /^\*\*Last updated:\*\*\s+[0-9]{4}-[0-9]{2}-[0-9]{2}\s*$/m.test(text)
  );
}

function validateManifest(manifest) {
  const errors = [];
  if (manifest.version !== 1) {
    errors.push("prototype-manifest.json must use version 1");
  }
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(manifest.last_updated || '')) {
    errors.push("prototype-manifest.json must include last_updated as YYYY-MM-DD");
  }
  if (typeof manifest.canonical_entry !== "string" || !manifest.canonical_entry.endsWith(".html")) {
    errors.push("prototype-manifest.json must include canonical_entry as a top-level HTML file");
  }
  if (!Array.isArray(manifest.entries)) {
    errors.push("prototype-manifest.json must include entries as an array");
    return errors;
  }

  const htmlFiles = listTopLevelHtml();
  const seen = new Set();
  const manifestPaths = [];
  const canonicalEntries = [];

  for (const [index, entry] of manifest.entries.entries()) {
    const label = `entry #${index + 1}`;
    if (!entry || typeof entry !== "object") {
      errors.push(`${label} must be an object`);
      continue;
    }
    const entryPath = entry.path;
    if (typeof entryPath !== "string" || !entryPath.endsWith(".html") || entryPath.includes("/")) {
      errors.push(`${label} must use a top-level HTML path`);
    } else {
      manifestPaths.push(entryPath);
      if (seen.has(entryPath)) {
        errors.push(`${entryPath} appears more than once in prototype-manifest.json`);
      }
      seen.add(entryPath);
      if (!fs.existsSync(path.join(root, entryPath))) {
        errors.push(`${entryPath} is listed but does not exist`);
      }
    }
    if (!allowedStatuses.has(entry.status)) {
      errors.push(`${entryPath || label} has invalid status: ${entry.status}`);
    }
    if (!allowedOwners.has(entry.owner)) {
      errors.push(`${entryPath || label} has invalid owner: ${entry.owner}`);
    }
    if (typeof entry.validation !== "string" || entry.validation.trim() === "") {
      errors.push(`${entryPath || label} must declare validation`);
    }
    if (typeof entry.notes !== "string" || entry.notes.trim() === "") {
      errors.push(`${entryPath || label} must include notes`);
    }
    if (entry.status === "canonical") {
      canonicalEntries.push(entryPath);
      if (entry.owner !== "Shell / Editor") {
        errors.push(`${entryPath} is canonical and must be owned by Shell / Editor`);
      }
      if (!String(entry.validation).includes("npm run selftest:editor")) {
        errors.push(`${entryPath} is canonical and must be covered by npm run selftest:editor`);
      }
    }
  }

  const missing = htmlFiles.filter((file) => !seen.has(file));
  const extra = manifestPaths.filter((file) => !htmlFiles.includes(file));
  if (missing.length) {
    errors.push(`top-level HTML files missing from prototype-manifest.json: ${missing.join(', ')}`);
  }
  if (extra.length) {
    errors.push(`manifest entries without matching HTML files: ${extra.join(', ')}`);
  }
  if (canonicalEntries.length !== 1) {
    errors.push(`prototype-manifest.json must declare exactly one canonical entry, found ${canonicalEntries.length}`);
  } else if (canonicalEntries[0] !== manifest.canonical_entry) {
    errors.push(`canonical_entry must match the canonical manifest entry: ${canonicalEntries[0]}`);
  }

  return errors;
}

function main() {
  const errors = [];
  if (!fs.existsSync(manifestPath)) {
    errors.push("prototype-manifest.json is missing");
  }
  if (!fs.existsSync(governancePath)) {
    errors.push("PROTOTYPE-GOVERNANCE.md is missing");
  } else {
    const text = fs.readFileSync(governancePath, "utf8");
    if (!hasMetadata(text)) {
      errors.push("PROTOTYPE-GOVERNANCE.md must include H1, Purpose, and Last updated metadata");
    }
    for (const required of ["canonical", "style-experiment", "npm run governance"]) {
      if (!text.includes(required)) {
        errors.push(`PROTOTYPE-GOVERNANCE.md must document ${required}`);
      }
    }
  }

  if (fs.existsSync(manifestPath)) {
    errors.push(...validateManifest(readJson(manifestPath)));
  }

  if (errors.length) {
    console.error("prototype governance failed:");
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }
  console.log("prototype governance passed");
}

main();
