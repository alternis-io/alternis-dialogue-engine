import { WasmHelper, makeWasmHelper, unmarshalString } from "./wasm";

export namespace DialogueContext {
  export namespace Slice {
    export function unmarshal(helper: WasmHelper, view: DataView) {
      // FIXME: support wasm64
      const dataPtr = view.getUint32(0, true);
      if (dataPtr === 0) return undefined;
      const len = view.getUint32(4, true);
      return unmarshalString(helper._instance, dataPtr, len);
    }

    export const byteSize = 8;
  }

  // FIXME: need a better name for this
  export namespace Strings {
    export function unmarshal(helper: WasmHelper, view: DataView) {
      const result: string[] = [];

      const dataPtr = view.getUint32(0, true);
      if (dataPtr === 0) return [];
      const len = view.getUint32(4, true);

      for (let i = 0; i < len; ++i) {
        const itemView = new DataView(view.buffer, dataPtr + i * Slice.byteSize);
        result.push(Slice.unmarshal(helper, itemView)!.value);
      }

      return result;
    }

    export const byteSize = 8;
  }

  export interface Line {
    speaker: string,
    text: string,
    metadata: string | undefined,
  }

  export namespace Line {
    export function unmarshal(helper: WasmHelper, view: DataView): Line {
      const speakerView = new DataView(view.buffer, view.byteOffset + 0);
      const speaker = Slice.unmarshal(helper, speakerView);
      if (speaker === undefined) throw Error("speaker was null");
      const textView = new DataView(view.buffer, view.byteOffset + 8);
      const text = Slice.unmarshal(helper, textView)
      if (text === undefined) throw Error("text was null");
      const metadataView = new DataView(view.buffer, view.byteOffset + 16);
      const metadata = Slice.unmarshal(helper, metadataView)


      return {
        speaker: speaker.value,
        text: text.value,
        metadata: metadata?.value,
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
    | { none: true }

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
        return { none: true };

      // next field should be padded over to next 4-byte alignment boundary
      const payloadView = new DataView(view.buffer, view.byteOffset + 4, view.byteLength - 4);

      if (tag == Tag.Options) {
        const textsView = new DataView(view.buffer, payloadView.byteOffset + 0);
        const strings = Strings.unmarshal(helper, textsView)
          .map(s => ({ text: s }));

        return { options: strings };
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
  ade_dialogue_ctx_create_json(json_ptr: number, json_len: number, random_seed: bigint, err: number): number;
  ade_dialogue_ctx_destroy(dialogue_ctx: number): void;
  ade_dialogue_ctx_step(dialogue_ctx: number, result_slot: number): void;
}

let _nativeModulePromise: Promise<WasmHelper<NativeModuleExports>> | undefined;

import initWasm from "../node_modules/alternis-wasm/zig-out/lib/alternis.wasm?init";

let importsInstance!: WebAssembly.Instance;

async function getNativeLib(): Promise<WasmHelper<NativeModuleExports>> {
  return _nativeModulePromise ??= initWasm({
    env: {
      _debug_print(ptr: number, len: number) { console.log(unmarshalString(importsInstance as any, ptr, len).value); },
    }
  }).then(inst => {
    importsInstance = inst;
    return makeWasmHelper<NativeModuleExports>(inst)
  });
}

/**
 * @param {string} json - a valid json string in the AlternisDialogueV1 format
 */
export async function makeDialogueContext(json: string): Promise<DialogueContext> {
  const nativeLib = await getNativeLib();
  const wasmJsonStr = nativeLib.marshalString(json);

  const errSlot = nativeLib._instance.exports.malloc(4); // wasm32 ptr bytesize
  // use a function to defer DataView creation since growth can invalidate the view
  const getErrView = () => new DataView(nativeLib._instance.exports.memory.buffer, errSlot);
  getErrView().setUint32(0, 0, true); // zero the memory

  const stepResultPtr = nativeLib._instance.exports.malloc(DialogueContext.StepResult.byteSize);
  const getStepResultView = () => new DataView(nativeLib._instance.exports.memory.buffer, stepResultPtr);

  const nativeDlgCtx = nativeLib._instance.exports.ade_dialogue_ctx_create_json(wasmJsonStr.ptr, wasmJsonStr.len, 0n, errSlot);
  const errPtr = getErrView().getUint32(0, true);
  if (errPtr !== 0) {
    const err = nativeLib.ptrToStr(errPtr);
    throw Error(err.value);
  }

  const result: DialogueContext = {
    step() {
      nativeLib._instance.exports.ade_dialogue_ctx_step(nativeDlgCtx, stepResultPtr);
      return DialogueContext.StepResult.unmarshal(nativeLib, getStepResultView());
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

  // currently the string is moved into dialogue context
  wasmJsonStr.free();

  return result;
}
