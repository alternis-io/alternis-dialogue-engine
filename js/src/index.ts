import { WasmHelper, makeWasmHelper } from "./wasm";

export namespace DialogueContext {
  export interface Line {
    speaker: string,
    text: string,
    metadata: string | undefined,
  }

  export namespace Line {
    export function unmarshal(helper: WasmHelper, view: DataView): Line {
      // FIXME: support wasm64
      const speaker_ptr = view.getUint32(0, true);
      const speaker_len = view.getUint32(4, true);
      const text_ptr = view.getUint32(8, true);
      const text_len = view.getUint32(12, true);
      const metadata_ptr = view.getUint32(16, true);
      const metadata_len = view.getUint32(20, true);

      // FIXME: leak
      return {
        speaker: helper.unmarshalString(speaker_ptr, speaker_len).value,
        text: helper.unmarshalString(text_ptr, text_len).value,
        metadata: metadata_ptr !== 0
          ? helper.unmarshalString(metadata_ptr, metadata_len).value
          : undefined,
      };
    }

    export const byteSize = 24;
  }

  export interface Option {
    text: string,
  }

  export type StepResult =
    | { line: Line }
    | { options: Option[] }
    | { none: null }

  // FIXME: generate this code
  export namespace StepResult {
    export enum Tag {
      None = 0,
      Options = 1,
      Line = 2,
    }

    export function unmarshal(helper: WasmHelper, view: DataView): StepResult {
      const tag = view.getUint8(0);
      if (tag == Tag.None)
        return { none: null };

      // next field should be padded over to next 4-byte alignment boundary
      const payloadView = new DataView(view.buffer, view.byteOffset + 4, view.byteLength - 4);

      if (tag == Tag.Options) {
        const options: Option[] = [];

        const texts_ptr = view.getUint32(4, true);
        const texts_len = view.getUint32(8, true);
        const byteSizeOfText = 8;
        const textsView = new DataView(helper._instance.exports.memory.buffer, texts_ptr, byteSizeOfText * texts_len);

        for (let i = 0; i < texts_len; ++i) {
          const text_ptr = textsView.getUint32(i * byteSizeOfText, true);
          const text_len = textsView.getUint32(i * byteSizeOfText + 4, true);
          options.push({
            // FIXME: leak
            text: helper.unmarshalString(text_ptr, text_len).value
          });
        }

        return { options };
      }

      if (tag == Tag.Line)
        return { line: Line.unmarshal(helper, payloadView) };

      throw Error("unreachable; unknown tag while unmarshalling StepResult")
    }

    // FIXME: assumes Line is the largest union member
    export const byteSize = 4 + Line.byteSize;
  }
}

export interface DialogueContext {
  step(): DialogueContext.StepResult;
  reset(): void;
  reply(replyId: number): void;
  // TODO: add support for Symbol.dispose
  dispose(): void;
}

interface NativeModuleExports {
  ade_dialogue_ctx_create_json(json_ptr: number, json_len: number): number;
  ade_dialogue_ctx_destroy(dialogue_ctx: number): void;
  ade_dialogue_ctx_step(dialogue_ctx: number, result_slot: number): void;
}

let _nativeModulePromise: Promise<WasmHelper<NativeModuleExports>> | undefined;

import initWasm from "../node_modules/alternis-wasm/zig-out/lib/alternis.wasm?init";

async function getNativeLib(): Promise<WasmHelper<NativeModuleExports>> {
  return _nativeModulePromise ??= initWasm().then(inst => makeWasmHelper<NativeModuleExports>(inst));
}

/**
 * @param {string} json - a valid json string in the AlternisDialogueV1 format
 */
export async function makeDialogueContext(json: string): Promise<DialogueContext> {
  const nativeLib = await getNativeLib();
  const wasmJsonStr = nativeLib.marshalString(json);
  const stepResultPtr = nativeLib._instance.exports.malloc(DialogueContext.StepResult.byteSize);
  const stepResultView = new DataView(nativeLib._instance.exports.memory.buffer.slice(stepResultPtr));
  const nativeDlgCtx = nativeLib._instance.exports.ade_dialogue_ctx_create_json(wasmJsonStr.ptr, wasmJsonStr.len);

  const result: DialogueContext = {
    step() {
      nativeLib._instance.exports.ade_dialogue_ctx_step(nativeDlgCtx, stepResultPtr);
      return DialogueContext.StepResult.unmarshal(nativeLib, stepResultView);
    },
    reset() {
      throw Error("unimplemented");
    },
    reply(replyId: number) {
      throw Error("unimplemented");
    },
    dispose() {
      nativeLib._instance.exports.free(stepResultPtr, DialogueContext.StepResult.byteSize);
      nativeLib._instance.exports.ade_dialogue_ctx_destroy(nativeDlgCtx);
    },
  };

  wasmJsonStr.free();

  return result;
}
