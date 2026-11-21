import { build } from "/app/dist/build.js";
import { resolveContentFolder } from "/app/dist/project-folder.js";

const projectDir = process.env.MDD_PROJECT_DIR;
const outputDir = process.env.MDD_OUTPUT_DIR;
const basePath = process.env.MDD_BASE_PATH;
const sourceDir = process.env.MDD_DOCS_DIR?.trim();
const sourceCommit = process.env.MDD_SOURCE_SHA?.trim();

if (!projectDir || !outputDir || !basePath) {
  console.error(
    "MDD_PROJECT_DIR, MDD_OUTPUT_DIR, and MDD_BASE_PATH are required.",
  );
  process.exit(1);
}

const mddDir = await resolveContentFolder(
  projectDir,
  sourceDir || undefined,
  "MDD_DOCS_DIR",
);

const result = await build({
  projectDir,
  mddDir,
  outDir: outputDir,
  basePath,
  sourceCommit: sourceCommit || undefined,
});

for (const diagnostic of result.diagnostics ?? []) {
  const location = diagnostic.file
    ? `${diagnostic.file}${diagnostic.line ? `:${diagnostic.line}` : ""}: `
    : "";
  console.error(
    `${location}${diagnostic.severity} ${diagnostic.code}: ${diagnostic.message}`,
  );
}

if (!result.site || !result.directory) {
  console.error(
    "MDD did not produce a site. Fix the documentation errors and run again.",
  );
  process.exit(1);
}

const pageCount = Array.isArray(result.site.pages) ? result.site.pages.length : 0;
console.log(`Built ${pageCount} pages into ${result.directory}.`);
