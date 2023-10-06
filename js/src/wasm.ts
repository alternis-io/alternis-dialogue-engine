function assert(condition: any, message?: string): asserts condition {
  if (!condition) throw Error(message ?? "AssertionError: condition was falsey");
}

type Pointer = number;

export type CompatibleWebAssemblyInstance = WebAssembly.Instance & {
  exports: {
    memory: WebAssembly.Memory;
    malloc(byte_count: number): Pointer;
    free(ptr: Pointer, len: number): void;
  }
}

export interface WasmStr {
  value: string;
  ptr: number;
  free(): void;
  len: number;
}

export function assertCompatibleWasmInstance(w: WebAssembly.Instance): asserts w is CompatibleWebAssemblyInstance {
  assert(w.exports.memory instanceof WebAssembly.Memory);
  assert(typeof w.exports.malloc === "function");
  assert(typeof w.exports.free === "function");
}

export interface WasmHelper<T extends Record<string, any> = {}> {
  _instance: CompatibleWebAssemblyInstance & { exports: T };
  marshalString(str: string): WasmStr;
  ptrToStr(ptr: number, encoding?: string): WasmStr;
  ptrAndLenToStr(ptr: number, len: number, encoding?: string): WasmStr;
  unmarshalString(ptr: number, len: number, encoding?: string): WasmStr;

  marshalSlice(str: string): WasmStr;
  unmarshalSlice(ptr: number, encoding?: string): WasmStr;
}

export function ptrToStr(inst: CompatibleWebAssemblyInstance, ptr: number, encoding?: string): WasmStr {
  // FIXME: why not use a data view?
  const slice = new Uint8Array(inst.exports.memory.buffer.slice(ptr));
  let i = 0;
  for (; i < slice.byteLength; ++i) {
    if (slice[i] === 0) break;
  }
  return ptrAndLenToStr(inst, ptr, i - 1, encoding);
}

export function ptrAndLenToStr(inst: CompatibleWebAssemblyInstance, ptr: number, len: number, encoding = "utf8"): WasmStr {
  const slice = inst.exports.memory.buffer.slice(ptr, ptr + len);
  return {
    value: new TextDecoder(encoding).decode(slice),
    ptr,
    len,
    free(this: WasmStr) { inst.exports.free(this.ptr, this.len); },
  };
}

export function marshalString(inst: CompatibleWebAssemblyInstance, str: string): WasmStr {
  const strBytes = new TextEncoder().encode(str);
  const allocPtr = inst.exports.malloc(strBytes.byteLength);
  const allocSlice = new DataView(inst.exports.memory.buffer, allocPtr, strBytes.byteLength);
  for (let i = 0; i < strBytes.byteLength; ++i) {
    allocSlice.setUint8(i, strBytes[i]);
  }
  return ptrAndLenToStr(inst, allocPtr, strBytes.byteLength);
}

export function unmarshalString(inst: CompatibleWebAssemblyInstance, ptr: number, len: number, encoding = "utf8"): WasmStr {
  return ptrAndLenToStr(inst, ptr, len, encoding);
}

export function makeWasmHelper<T extends Record<string, any> = {}>(wasmInst: WebAssembly.Instance): WasmHelper<T> {
  assertCompatibleWasmInstance(wasmInst);

  return {
    _instance: wasmInst as CompatibleWebAssemblyInstance & { exports: T },
    ptrToStr: (...args) => ptrToStr(wasmInst, ...args),
    ptrAndLenToStr: (...args) => ptrAndLenToStr(wasmInst, ...args),
    marshalString: (...args) => marshalString(wasmInst, ...args),
    unmarshalString: (...args) => unmarshalString(wasmInst, ...args),

    marshalSlice(str: string): WasmStr {
      throw Error("unimplemented");
    },

    unmarshalSlice(ptr: number, encoding = "utf8"): WasmStr {
      const view = new DataView(wasmInst.exports.memory.buffer, ptr);
      const data = view.getUint32(0, true);
      const len = view.getUint32(4, true);
      return unmarshalString(wasmInst, data, len, encoding)
    }
  }
}
