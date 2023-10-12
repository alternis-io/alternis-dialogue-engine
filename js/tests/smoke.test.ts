import * as Api from "../dist/alternis.js";
import * as WorkerApi from "../dist/alternis-worker.js";
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert";

// FIXME: load from alternis-wasm dependency
const smallTestJson = fs.readFileSync(
  new URL("../node_modules/alternis-wasm/test/assets/simple1.alternis.json", import.meta.url),
  { encoding: "utf8" }
);

describe("smoke", () => {
  it("create and run small context to completion", async () => {
    const ctx = await Api.makeDialogueContext(smallTestJson);

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
      done: true,
    });

    ctx.dispose();
  });

  it("create and run large context to completion", async () => {
    // FIXME: load from alternis-wasm dependency
    const largeTestJson = fs.readFileSync(
      new URL("../node_modules/alternis-wasm/test/assets/sample1.alternis.json", import.meta.url),
      { encoding: "utf8" }
    );

    const ctx = await Api.makeDialogueContext(largeTestJson);

    ctx.setCallback("ask player name", async () => {
      await new Promise(r => setTimeout(r, 50));
      ctx.setVariableString("name", "Testy McTester");
    });

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aisha",
        text: "Hey",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aaron",
        text: "Yo",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aaron",
        text: "What's your name?",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      functionCalled: true,
    });

    assert.deepStrictEqual(ctx.step(), {
      options:  {
        texts: [
          {
            speaker: "Aisha",
            text: "It's Testy McTester and I like waffles",
          },
          {
            speaker: "Aisha",
            text: "It's Testy McTester",
          },
        ],
        ids: [0, 1],
      },
    });

    // if we don't reply, we get the same node
    assert.deepStrictEqual(ctx.step(), {
      options:  {
        texts: [
          {
            speaker: "Aisha",
            text: "It's Testy McTester and I like waffles",
          },
          {
            speaker: "Aisha",
            text: "It's Testy McTester",
          },
        ],
        ids: [0, 1],
      },
    });

    ctx.reply(1);

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aaron",
        text: "Ok. What was your name again?",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      options:  {
        texts: [
          {
            speaker: "Aisha",
            text: "It's Testy McTester and I like waffles",
          },
          {
            speaker: "Aisha",
            text: "It's Testy McTester",
          },
        ],
        ids: [0, 1],
      },
    });

    ctx.reply(0);

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aaron",
        text: "You're pretty cool!\nWhat was your name again?",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      options:  {
        texts: [
          {
            speaker: "Aisha",
            text: "It's Testy McTester and I like waffles",
          },
          {
            speaker: "Aisha",
            text: "It's Testy McTester",
          },
          {
            speaker: "Aisha",
            text: "Wanna go eat waffles?",
          },
        ],
        ids: [0, 1, 2],
      },
    });

    ctx.reply(2);

    assert.deepStrictEqual(ctx.step(), {
      line:  {
        speaker: "Aaron",
        text: "Yeah, Testy McTester.",
        metadata: undefined,
      },
    });

    assert.deepStrictEqual(ctx.step(), {
      done: true,
    });

    ctx.dispose();
  });

  it("create and run worker context to completion", async () => {
    const ctx = await WorkerApi.makeDialogueContext(smallTestJson);

    const step_result_1 = await ctx.step();
    assert.deepStrictEqual(step_result_1, {
      line:  {
        speaker: "test",
        text: "hello world!",
        metadata: undefined,
      },
    });

    const step_result_2 = await ctx.step();
    assert.deepStrictEqual(step_result_2, {
      line:  {
        speaker: "test",
        text: "goodbye cruel world!",
        metadata: undefined,
      },
    });

    const step_result_3 = await ctx.step();
    assert.deepStrictEqual(step_result_3, {
      done: true,
    });

    await ctx.dispose();
  });
});
