import { makeDialogueContext } from "../dist/alternis.js";
import assert from "assert";

// FIXME: load from alternis-wasm dependency
const smallTestJson = {
  "entryId": 0,
  "nodes": [
    {
      "id": 0,
      "line": {
        "data": {
          "speaker": "test",
          "text": "hello world!"
        },
        "next": 1
      }
    },
    {
      "id": 1,
      "line": {
        "data": {
          "speaker": "test",
          "text": "goodbye cruel world!"
        }
      }
    }
  ]
}

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
      none: undefined,
    });

    ctx.dispose();
  });
});
