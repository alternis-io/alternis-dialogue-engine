import type * as InContextApi from ".";

const worker = new Worker(new URL("./worker.ts", import.meta.url), {
  name: "AlternisWasmWorker",
  type: "module",
});

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
