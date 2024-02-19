import type * as InContextApi from ".";
import MyWorker from "./worker.ts?worker";

// FIXME: use a dependency?
interface UnifiedWorker<Msg = any> {
  addEventListener(evt: "message", handler: (msg: Msg) => void): void;
  removeEventListener(evt: "message", handler: (msg: Msg) => void): void;
  postMessage(msg: Msg): void;
}

let worker: UnifiedWorker;

async function getWorker() {
  if (!worker) {
    if("Worker" in globalThis) {
      const WorkerClass = globalThis.Worker;
      // const _worker = new WorkerClass(new URL("./worker", import.meta.url), {
      //   name: "AlternisWasmWorker",
      //   type: "module",
      // });
      const _worker = new MyWorker({
        name: "AlternisWasmWorker",
        type: "module",
      });

      worker = {
        addEventListener: (...args) => _worker.addEventListener(...args),
        removeEventListener: (...args) => _worker.removeEventListener(...args),
        postMessage: (...args) => _worker.postMessage(...args),
      };
    } else {
      // FIXME: this doesn't work
      // HACK: vite uses self and I can't tell how best to make it emit node-compatible
      // output
      (globalThis as any).self = { location: import.meta.url };
      const WorkerClass = await import("node:worker_threads").then(p => p.Worker)
      const _worker = new WorkerClass(await import("./worker.ts?url"), {
        name: "AlternisWasmWorker",
      });
      delete (globalThis as any).self;

      worker = {
        addEventListener: (...args) => _worker.addListener(...args),
        removeEventListener: (...args) => _worker.removeListener(...args),
        postMessage: (...args) => _worker.postMessage(...args),
      };
    }
  }

  return worker;
}


export interface WorkerDialogueContext {
  step(dialogue_id: number): Promise<InContextApi.DialogueContext.StepResult>;
  reset(dialogue_id: number, node_id: number): Promise<void>;
  reply(dialogue_id: number, replyId: number): Promise<void>;
  getNodeByLabel(dialogue_id: number, label: string): Promise<number>;
  // TODO: add support for Symbol.dispose
  dispose(): void;
}

let msgId = 0;
const getMsgId = () => msgId++;

async function asyncPostMessageWithId(msg: Record<string, any>) {
  const worker = await getWorker();

  return new Promise<any>((resolve, reject) => {
    const id = getMsgId();
    const handler = (msg: any) => {
      if (msg.data.id !== id) return;
      worker.removeEventListener("message", handler);
      if (msg.data.error) reject(msg.data.error)
      else resolve(msg.data.result);
    };
    worker.addEventListener("message", handler);
    worker.postMessage({ ...msg, id });
  });
}

export async function makeDialogueContext(
  ...args: Parameters<typeof InContextApi.makeDialogueContext>
): Promise<WorkerDialogueContext> {
  const result = await asyncPostMessageWithId({ type: "makeDialogueContext", args });

  return {
    async step(dialogue_id) {
      return await asyncPostMessageWithId({ type: "DialogueContext.step", ptr: result.ptr, args: [dialogue_id] });
    },
    async reset(dialogue_id, node_id = 0) {
      return asyncPostMessageWithId({ type: "DialogueContext.reset", ptr: result.ptr, args: [dialogue_id, node_id] });
    },
    async reply(dialogue_id, replyId) {
      return asyncPostMessageWithId({ type: "DialogueContext.reply", ptr: result.ptr, args: [dialogue_id, replyId] });
    },
    async getNodeByLabel(dialogue_id, label) {
      return asyncPostMessageWithId({ type: "DialogueContext.getNodeByLabel", ptr: result.ptr, args: [dialogue_id, label] });
    },
    async dispose() {
      return asyncPostMessageWithId({ type: "DialogueContext.dispose", ptr: result.ptr });
    },
  };
}
