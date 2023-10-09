import { makeDialogueContext } from "../dist/alternis.js";
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert";

// FIXME: load from alternis-wasm dependency
const smallTestJson = fs.readFileSync(
  new URL("../node_modules/alternis-wasm/test/assets/simple1.alternis.json", import.meta.url)
);

describe("smoke", () => {
  it("create and run context to completion", async () => {
    const ctx = await makeDialogueContext(JSON.stringify(smallTestJson));

    const step_result_1 = ctx.step();
    assert.deepStrictEqual(step_result_1, {
      line:  {
        speaker: "test",
        text: "hello world!",
        metadata: undefined,
      },
    });

    const step_result_2 = ctx.step();
    assert.deepStrictEqual(step_result_2, {
      line:  {
        speaker: "test",
        text: "goodbye cruel world!",
        metadata: undefined,
      },
    });

    const step_result_3 = ctx.step();
    assert.deepStrictEqual(step_result_3, {
      none: true,
    });

    ctx.dispose();
  });

  it("create and run worker context to completion", async () => {
    const ctx = await makeDialogueContext(JSON.stringify(smallTestJson));

    const step_result_1 = ctx.step();
    assert.deepStrictEqual(step_result_1, {
      line:  {
        speaker: "test",
        text: "hello world!",
        metadata: undefined,
      },
    });

    const step_result_2 = ctx.step();
    assert.deepStrictEqual(step_result_2, {
      line:  {
        speaker: "test",
        text: "goodbye cruel world!",
        metadata: undefined,
      },
    });

    const step_result_3 = ctx.step();
    assert.deepStrictEqual(step_result_3, {
      none: true,
    });

    ctx.dispose();
  });
});
