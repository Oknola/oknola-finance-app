// Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const SOURCE = "design/tokens/sure.tokens.json";

function withGenerator(script, output, callback) {
  const root = mkdtempSync(join(tmpdir(), "oknola-tokens-"));
  try {
    for (const path of [script, output, SOURCE]) {
      mkdirSync(dirname(join(root, path)), { recursive: true });
    }
    copyFileSync(join(ROOT, script), join(root, script));
    const tokens = JSON.parse(readFileSync(join(ROOT, SOURCE), "utf8"));
    const build = () => {
      writeFileSync(join(root, SOURCE), JSON.stringify(tokens));
      return spawnSync(process.execPath, [join(root, script)], { encoding: "utf8" });
    };
    callback(tokens, build, () => readFileSync(join(root, output), "utf8"));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test("CSS literal colors and references preserve dark variables and class lists", () => {
  withGenerator("bin/tokens.mjs", "app/assets/tailwind/sure-design-system/_generated.css", (tokens, build, read) => {
    tokens.utility["text-primary"].$value = "#abc";
    tokens.utility["text-primary"].$extensions["sure.dark"] = "{color.white}";
    tokens.utility["text-secondary"].$value = "{color.gray.500}";
    tokens.utility["text-secondary"].$extensions["sure.dark"] = "#12345678";
    tokens.utility["border-divider"].$value = "#1234";
    tokens.utility["border-divider"].$extensions = { "sure.utility": { prefix: "border" } };
    const result = build();
    assert.equal(result.status, 0, result.stderr);
    const css = read();
    for (const expected of [
      "@apply text-[#abc];",
      "--utility-text-primary: var(--color-white);",
      "@apply text-(--utility-text-primary);",
      "--utility-text-secondary: #12345678;",
      "@apply text-(--utility-text-secondary);",
      "@apply border-[#1234];",
      "@apply bg-gray-800 text-inverse;",
      "@apply bg-surface-inset animate-pulse;",
    ]) assert.ok(css.includes(expected), expected);
    assert.doesNotMatch(css, /@apply #/);
  });
});

test("CSS canonical literal colors generate deterministic light and dark output", () => {
  withGenerator("bin/tokens.mjs", "app/assets/tailwind/sure-design-system/_generated.css", (_tokens, build, read) => {
    assert.equal(build().status, 0);
    const css = read();
    assert.ok(css.includes("@apply text-[#1A1714];"));
    assert.ok(css.includes("--utility-text-primary: #EDE4D6;"));
    assert.equal(build().status, 0);
    assert.equal(read(), css);
    assert.equal(css, readFileSync(join(ROOT, "app/assets/tailwind/sure-design-system/_generated.css"), "utf8"));
  });
});

test("mobile rgba colors and shadows round alpha and preserve geometry and references", () => {
  withGenerator("mobile/tool/generate_sure_tokens.mjs", "mobile/lib/theme/sure_tokens.dart", (tokens, build, read) => {
    tokens.color.shadow.$value = "rgba(60, 45, 20, 0.08)";
    tokens.color.shadow.$extensions["sure.dark"] = "rgba(0, 128, 255, 1)";
    tokens.shadow.sm.$value = "0px 1px 0px 0px rgba(60, 45, 20, .45)";
    tokens.shadow.xs.$value = "-1px 2px 3px -4px #123456";
    const result = build();
    assert.equal(result.status, 0, result.stderr);
    const dart = read();
    for (const expected of [
      "shadow: Color(0x143C2D14)",
      "shadow: Color(0xFF0080FF)",
      "BoxShadow(color: Color(0x733C2D14), offset: Offset(0.0, 1.0), blurRadius: 0.0, spreadRadius: 0.0)",
      "BoxShadow(color: Color(0xFF123456), offset: Offset(-1.0, 2.0), blurRadius: 3.0, spreadRadius: -4.0)",
      "Color(0x14FFFFFF)",
    ]) assert.ok(dart.includes(expected), expected);
    tokens.color.shadow.$value = "rgba( 255, 0, 128, 0 )";
    assert.equal(build().status, 0);
    assert.ok(read().includes("shadow: Color(0x00FF0080)"));
  });
});

test("mobile generator rejects malformed rgba colors and shadows", () => {
  withGenerator("mobile/tool/generate_sure_tokens.mjs", "mobile/lib/theme/sure_tokens.dart", (tokens, build) => {
    for (const value of [
      "rgba(256, 0, 0, 1)", "rgba(0, 0, 0, 1.1)",
      "rgba(-1, 0, 0, 1)", "rgba(0, 0, 0, -0.1)",
      "rgba(0, 0, 0, NaN)", "rgba(1.5, 0, 0, 1)",
    ]) {
      tokens.color.shadow.$value = value;
      const result = build();
      assert.equal(result.status, 1, value);
      assert.match(result.stderr, /\[mobile-tokens\]/);
    }
    tokens.color.shadow.$value = "{color.black|6%}";
    tokens.shadow.sm.$value = "0px 1px 0px 0px rgba(0, 0, 0, 2)";
    assert.equal(build().status, 1);
    tokens.shadow.sm.$value = "0px 1px -2px 0px rgba(0, 0, 0, 1)";
    assert.equal(build().status, 1);
  });
});
