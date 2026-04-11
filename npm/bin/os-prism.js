#!/usr/bin/env node
// Thin shim — defers to the compiled CLI under dist/.
import("../dist/cli.js").catch((err) => {
  console.error("[os-prism] failed to start:", err?.stack ?? err);
  process.exit(1);
});
