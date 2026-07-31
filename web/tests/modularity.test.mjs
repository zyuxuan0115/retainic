import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const sourceExtensions = new Set([
  ".css",
  ".html",
  ".java",
  ".js",
  ".jsx",
  ".kt",
  ".kts",
  ".m",
  ".mm",
  ".py",
  ".rb",
  ".rs",
  ".swift",
  ".ts",
  ".tsx",
]);
const ignoredDirectories = new Set([
  ".git",
  ".gradle",
  "DerivedData",
  "build",
  "graphify-out",
  "node_modules",
]);

async function sourceFiles(directory) {
  const files = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isDirectory() && ignoredDirectories.has(entry.name)) continue;
    const location = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await sourceFiles(location));
    else if (sourceExtensions.has(path.extname(entry.name))) files.push(location);
  }
  return files;
}

test("source modules do not exceed 600 lines", async () => {
  const oversized = [];
  for (const file of await sourceFiles(repositoryRoot)) {
    const source = await readFile(file, "utf8");
    const lineCount = source.length === 0
      ? 0
      : source.split(/\r\n|\r|\n/).length - (/(?:\r\n|\r|\n)$/.test(source) ? 1 : 0);
    if (lineCount > 600) {
      oversized.push(`${path.relative(repositoryRoot, file)} (${lineCount} lines)`);
    }
  }
  assert.deepEqual(oversized, []);
});
