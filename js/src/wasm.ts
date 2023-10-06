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
  assert(typeof w.exports.alloc_string === "function");
  assert(typeof w.exports.free_string === "function");
}

export interface WasmHelper<T extends Record<string, any> = {}> {
  _instance: CompatibleWebAssemblyInstance & { exports: T };
  marshalString(str: string): WasmStr;
  ptrToStr(ptr: number, encoding?: string): WasmStr;
  ptrAndLenToStr(ptr: number, len: number, encoding?: string): WasmStr;
  unmarshalString(ptr: number, len: number, encoding?: string): WasmStr;

  marshalSlice(str: string): WasmStr;
  unmarshalSlice(ptr: number, len: number, encoding?: string): WasmStr;
}

export function makeWasmHelper<T extends Record<string, any> = {}>(wasmInst: WebAssembly.Instance): WasmHelper<T> {
  assertCompatibleWasmInstance(wasmInst);

  return {
    _instance: wasmInst as CompatibleWebAssemblyInstance & { exports: T },

    ptrToStr(ptr: number, encoding?: string): WasmStr {
      const slice = new Uint8Array(wasmInst.exports.memory.buffer.slice(ptr));
      let i = 0;
      for (; i < slice.byteLength; ++i) {
        if (slice[i] === 0) break;
      }
      return this.ptrAndLenToStr(ptr, i - 1, encoding);
    },

    ptrAndLenToStr(ptr: number, len: number, encoding = "utf8"): WasmStr {
      const slice = wasmInst.exports.memory.buffer.slice(ptr, ptr + len);
      return {
        value: new TextDecoder(encoding).decode(slice),
        ptr,
        len,
        free(this: WasmStr) { wasmInst.exports.free(this.ptr, this.len); },
      };
    },

    marshalString(str: string): WasmStr {
      const strBytes = new TextEncoder().encode(str);
      const allocPtr = wasmInst.exports.malloc(strBytes.byteLength);
      const allocSlice = new DataView(wasmInst.exports.memory.buffer, allocPtr, strBytes.byteLength);
      for (let i = 0; i < strBytes.byteLength; ++i) {
        allocSlice.setUint8(i, strBytes[i]);
      }
      return this.ptrAndLenToStr(allocPtr, strBytes.byteLength);
    },

    unmarshalString(ptr: number, len: number, encoding = "utf8"): WasmStr {
      return this.ptrAndLenToStr(ptr, len, encoding);
    },

    marshalSlice(str: string): WasmStr {
      throw Error("unimplemented");
    },

    unmarshalSlice(ptr: number, len: number, encoding = "utf8"): WasmStr {
      throw Error("unimplemented");
    }
  }
}
