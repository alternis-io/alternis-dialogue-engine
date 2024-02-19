import { WasmHelper, WasmStr, makeWasmHelper, unmarshalString } from "./wasm";

// FIXME: move unmarshalling stuff to separate file
interface Unmarshallable<T> {
  unmarshal(helper: WasmHelper, view: DataView): T;
  byteSize: number;
}

export namespace DialogueContext {
  const Slice = <T,>(unmarshaller: Unmarshallable<T>) => {
    return {
      unmarshal(helper: WasmHelper, view: DataView) {
        const result: T[] = [];

        const dataPtr = view.getUint32(0, true);
        if (dataPtr === 0) return [];
        const len = view.getUint32(4, true);

        for (let i = 0; i < len; ++i) {
          const itemView = new DataView(view.buffer, dataPtr + i * unmarshaller.byteSize);
          result.push(unmarshaller.unmarshal(helper, itemView));
        }

        return result;
      },

      byteSize: 8,
    };
  };

  export namespace StringSlice {
    export function unmarshal(helper: WasmHelper, view: DataView): WasmStr | undefined {
      // FIXME: support wasm64
      const dataPtr = view.getUint32(0, true);
      if (dataPtr === 0) return undefined;
      const len = view.getUint32(4, true);
      return unmarshalString(helper._instance, dataPtr, len);
    }

    export const byteSize = 8;
  }

  export namespace USizeSlice {
    export function unmarshal(_helper: WasmHelper, view: DataView): number[] | undefined {
      // FIXME: support wasm64
      const dataPtr = view.getUint32(0, true);
      if (dataPtr === 0) return undefined;
      const len = view.getUint32(4, true);

      const result: number[] = [];

      const usizeByteSize = 4;
      for (let i = 0; i < len; ++i) {
        // FIXME: technically would be faster to not keep creating new data views
        const itemView = new DataView(view.buffer, dataPtr + i * usizeByteSize);
        result.push(itemView.getUint32(0, true));
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
      const speakerView = new DataView(view.buffer, view.byteOffset + 0 * StringSlice.byteSize);
      const speaker = StringSlice.unmarshal(helper, speakerView);
      if (speaker === undefined) throw Error("speaker was null");
      const textView = new DataView(view.buffer, view.byteOffset + 1 * StringSlice.byteSize);
      const text = StringSlice.unmarshal(helper, textView)
      if (text === undefined) throw Error("text was null");
      const metadataView = new DataView(view.buffer, view.byteOffset + 2 * StringSlice.byteSize);
      const metadata = StringSlice.unmarshal(helper, metadataView)


      return {
        speaker: speaker.value,
        text: text.value,
        metadata: metadata?.value,
      };
    }

    export const byteSize = 3 * StringSlice.byteSize;
  }

  export interface Option {
    id: number,
    text: string,
  }

  export type StepResult =
    | { line: Line }
    | { options: Option[] }
    | { done: true }
    | { functionCalled: true }

  // FIXME: generate this code
  export namespace StepResult {
    export enum Tag {
      Done = 0,
      Options = 1,
      Line = 2,
      FunctionCalled = 3,
    }

    export function unmarshal(helper: WasmHelper, view: DataView): StepResult {
      const tag = view.getUint8(0);
      if (tag == Tag.Done)
        return { done: true };

      // next field should be padded over to next 4-byte alignment boundary
      const payloadView = new DataView(view.buffer, view.byteOffset + 4, view.byteLength - 4);

      if (tag == Tag.Options) {
        const textsView = new DataView(view.buffer, payloadView.byteOffset + 0);
        const strings = Slice(Line).unmarshal(helper, textsView);
        const idsView = new DataView(view.buffer, payloadView.byteOffset + Slice(Line).byteSize);
        const ids = USizeSlice.unmarshal(helper, idsView) ?? [];

        return {
          options: strings.map((s, i) => ({
            ...s,
            id: ids[i],
          })),
        };
      }

      if (tag == Tag.Line)
        return { line: Line.unmarshal(helper, payloadView) };

      if (tag == Tag.FunctionCalled)
        return { functionCalled: true };

      throw Error("unreachable; unknown tag while unmarshalling StepResult")
    }

    // NOTE: union types list be synced manually
    export const byteSize = 4 + Math.max(Line.byteSize, Slice(Line).byteSize);
  }
}

export interface DialogueContext {
  // FIXME: reference dialogues by name
  step(dialogue_id: number): DialogueContext.StepResult;
  /** reset to the given node_id. 0 always refers to the first node */
  reset(dialogue_id: number, node_id?: number): void;
  reply(dialogue_id: number, replyId: number): void;
  /** returns the numeric id of the node for a given label,
   * which can be used to reset to that node programmatically
   */
  getNodeByLabel(dialogue_id: number, name: string): number;

  // TODO: support promises
  setCallback(name: string, fn: (() => void)): void;
  setVariableBoolean(name: string, value: boolean): void;
  setVariableString(name: string, value: string): void;

  // TODO: add support for Symbol.dispose
  dispose(): void;
}

interface NativeModuleExports {
  ade_dialogue_ctx_create_json(
    json_ptr: number,
    json_len: number,
    random_seed: bigint,
    no_interpolate: 0 | 1,
    err: number
  ): number;

  ade_dialogue_ctx_destroy(dialogue_ctx: number): void;

  ade_dialogue_ctx_step(dialogue_ctx: number, dialogue_id: number, result_slot: number): void;
  ade_dialogue_ctx_reset(dialogue_ctx: number, dialogue_id: number, node_index: number): void;
  ade_dialogue_ctx_reply(dialogue_ctx: number, dialogue_id: number, reply_id: number): void;
  ade_dialogue_ctx_get_node_by_label(dialogue_ctx: number, dialogue_id: number, label_ptr: number, label_len: number): number;

  ade_dialogue_ctx_set_variable_boolean(
    in_dialogue_ctx: number,
    name: number,
    len: number,
    value: 0 | 1,
  ): void;

  ade_dialogue_ctx_set_variable_string(
    in_dialogue_ctx: number,
    name: number,
    len: number,
    value_ptr: number,
    value_len: number,
  ): void;

  ade_dialogue_ctx_set_callback_js(
    in_dialogue_ctx: number,
    name: number,
    len: number,
  ): number;
}

let _nativeModulePromise: Promise<WasmHelper<NativeModuleExports>> | undefined;

import initWasm from "../node_modules/alternis-wasm/zig-out/lib/alternis.wasm?init";

let importsInstance!: WebAssembly.Instance;

const handleToJsFuncMap = new Map<number, () => void>();

async function getNativeLib(): Promise<WasmHelper<NativeModuleExports>> {
  return _nativeModulePromise ??= initWasm({
    env: {
      _debug_print(ptr: number, len: number) {
        console.log(unmarshalString(importsInstance as any, ptr, len).value);
      },
      _call_js(handle: number) {
        const jsFunc = handleToJsFuncMap.get(handle);
        if (jsFunc === undefined) throw Error("no such handle!");
        jsFunc();
      }
    }
  }).then(inst => {
    importsInstance = inst;
    return makeWasmHelper<NativeModuleExports>(inst)
  });
}

interface MakeDialogueContextOpts {
  /** @default use Math.random() for a random seed */
  randomSeed?: bigint;
  /** @default false */
  noInterpolate?: boolean;
}

declare global {
  var __alternis: undefined | {
    MAX_STEP_ITERS?: number;
  };
}

/**
 * @param {string} json - a valid json string in the AlternisDialogueV1 format
 */
export async function makeDialogueContext(json: string, opts: MakeDialogueContextOpts = {}): Promise<DialogueContext> {
  const nativeLib = await getNativeLib();
  const wasmJsonStr = nativeLib.marshalString(json);

  const randomSeed = opts.randomSeed ?? BigInt(Math.floor(Math.random() * Number.MAX_SAFE_INTEGER));
  const noInterpolate = (opts.noInterpolate ?? false) ? 1 : 0;

  const errSlot = nativeLib._instance.exports.malloc(4); // wasm32 ptr bytesize
  // use a function to defer DataView creation since growth can invalidate the view
  const getErrView = () => new DataView(nativeLib._instance.exports.memory.buffer, errSlot);
  getErrView().setUint32(0, 0, true); // zero the memory

  const stepResultPtr = nativeLib._instance.exports.malloc(DialogueContext.StepResult.byteSize);
  const getStepResultView = () => new DataView(nativeLib._instance.exports.memory.buffer, stepResultPtr);

  const nativeDlgCtx = nativeLib._instance.exports.ade_dialogue_ctx_create_json(wasmJsonStr.ptr, wasmJsonStr.len, randomSeed, noInterpolate, errSlot);
  const errPtr = getErrView().getUint32(0, true);

  if (errPtr !== 0) {
    const err = nativeLib.ptrToStr(errPtr);
    throw Error(err.value);
  }

  /** table of js strings already stored in wasm */
  const stringTable = new Map<string, WasmStr>();

  const result: DialogueContext = {
    step(dialogue_id) {
      let stepResult: DialogueContext.StepResult;

      const MAX_ITERS = globalThis?.__alternis?.MAX_STEP_ITERS ?? 500_000;
      if (MAX_ITERS <= 0) throw Error(`invalid globalThis.__alternis.MAX_STEP_ITERS of '${MAX_ITERS}'`);

      for (let i = 0; i < MAX_ITERS; ++i) {
        nativeLib._instance.exports.ade_dialogue_ctx_step(nativeDlgCtx, dialogue_id, stepResultPtr);
        stepResult = DialogueContext.StepResult.unmarshal(nativeLib, getStepResultView());
        if ("functionCalled" in stepResult)
          continue;
        break;
      }

      return stepResult!;
    },

    reset(dialogue_id, node_id = 0) {
      // FIXME: test for handling invalid ids
      nativeLib._instance.exports.ade_dialogue_ctx_reset(nativeDlgCtx, dialogue_id, node_id);
    },

    reply(dialogue_id, replyId) {
      nativeLib._instance.exports.ade_dialogue_ctx_reply(nativeDlgCtx, dialogue_id, replyId);
    },

    getNodeByLabel(dialogue_id, name) {
      let wasmName = stringTable.get(name);
      if (wasmName === undefined) {
        wasmName = nativeLib.marshalString(name);
        stringTable.set(name, wasmName);
      }
      return nativeLib._instance.exports.ade_dialogue_ctx_get_node_by_label(nativeDlgCtx, dialogue_id, wasmName.ptr, wasmName.len);
    },

    setCallback(name, cb) {
      let wasmName = stringTable.get(name);
      if (wasmName === undefined) {
        wasmName = nativeLib.marshalString(name);
        stringTable.set(name, wasmName);
      }
      const handle = nativeLib._instance.exports.ade_dialogue_ctx_set_callback_js(nativeDlgCtx, wasmName.ptr, wasmName.len);
      const INVALID_CALLBACK_HANDLE = 0;
      if (handle === INVALID_CALLBACK_HANDLE)
        throw Error("invalid callback handle received, is the dialogue context pointer valid?");
      handleToJsFuncMap.set(handle, cb);
    },

    setVariableBoolean(name, value) {
      let wasmName = stringTable.get(name);
      if (wasmName === undefined) {
        wasmName = nativeLib.marshalString(name);
        stringTable.set(name, wasmName);
      }

      nativeLib._instance.exports.ade_dialogue_ctx_set_variable_boolean(nativeDlgCtx, wasmName.ptr, wasmName.len, value ? 1 : 0);
    },

    setVariableString(name, value) {
      let wasmName = stringTable.get(name);
      if (wasmName === undefined) {
        wasmName = nativeLib.marshalString(name);
        stringTable.set(name, wasmName);
      }

      let wasmValue = stringTable.get(value);
      if (wasmValue === undefined) {
        wasmValue = nativeLib.marshalString(value);
        stringTable.set(value, wasmValue);
      }

      nativeLib._instance.exports.ade_dialogue_ctx_set_variable_string(nativeDlgCtx, wasmName.ptr, wasmName.len, wasmValue.ptr, wasmValue.len);
    },

    dispose() {
      nativeLib._instance.exports.free(stepResultPtr, DialogueContext.StepResult.byteSize);
      nativeLib._instance.exports.ade_dialogue_ctx_destroy(nativeDlgCtx);
      for (const wasmStr of stringTable.values())
        wasmStr.free();
    },
  };

  // currently the string is moved into dialogue context
  wasmJsonStr.free();

  return result;
}
