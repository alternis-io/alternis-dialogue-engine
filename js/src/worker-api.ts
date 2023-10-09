import type * as InContextApi from ".";

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
      const _worker = new WorkerClass(new URL("./worker.ts", import.meta.url), {
        name: "AlternisWasmWorker",
        type: "module",
      });

      worker = {
        addEventListener: (...args) => _worker.addEventListener(...args),
        removeEventListener: (...args) => _worker.removeEventListener(...args),
        postMessage: _worker.postMessage,
      };
    } else {
      // HACK: vite uses self and doesn't seem to want to make something node compatible
      (globalThis as any).self = globalThis;
      const WorkerClass = await import("node:worker_threads").then(p => p.Worker)
      const _worker = new WorkerClass(new URL("./worker.ts", import.meta.url), {
        name: "AlternisWasmWorker",
      });

      worker = {
        addEventListener: (...args) => _worker.addListener(...args),
        removeEventListener: (...args) => _worker.removeListener(...args),
        postMessage: _worker.postMessage,
      };
    }
  }

  return worker;
}


export interface WorkerDialogueContext {
  step(): Promise<InContextApi.DialogueContext.StepResult>;
  reset(): Promise<void>;
  reply(replyId: number): Promise<void>;
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
      if (msg.id !== id) return;
      worker.removeEventListener("message", handler);
      if (msg.error) reject(msg.error)
      else resolve(msg.result);
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
    async step() {
      return await asyncPostMessageWithId({ type: "DialogueContext.step", ptr: result.ptr });
    },
    async reset() {
      return asyncPostMessageWithId({ type: "DialogueContext.reset", ptr: result.ptr });
    },
    async reply(replyId) {
      return asyncPostMessageWithId({ type: "DialogueContext.reply", ptr: result.ptr, args: [replyId] });
    },
    async dispose() {
      return asyncPostMessageWithId({ type: "DialogueContext.dispose", ptr: result.ptr });
    },
  };
}
