import { DialogueContext, makeDialogueContext } from ".";

const ptrMap = new Map<number, DialogueContext>();

const onmessagePromise: Promise<(msg: any) => any>
  = "onmessage" in globalThis
  ? Promise.resolve(
      (handler: (msg: any) => any) =>
        globalThis.onmessage = (ev: MessageEvent) => handler(ev.data)
    )
  : import("node:worker_threads").then(m =>
      (handler) => m.parentPort!.on("message", handler)
    );

onmessagePromise.then(onmessage => onmessage(async (msg: any) => {
  const id = msg.id;

  try {
    if (msg.type === "makeDialogueContext") {
      const newCtx = await makeDialogueContext(...msg.args as [any, any]);
      ptrMap.set(id, newCtx);
      postMessage({ id, ptr: id });

    } else if (msg.type === "DialogueContext.step") {
      const ctx = ptrMap.get(msg.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.step() });

    } else if (msg.type === "DialogueContext.reset") {
      const ctx = ptrMap.get(msg.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.reset() });

    } else if (msg.type === "DialogueContext.reply") {
      const ctx = ptrMap.get(msg.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.reply(...msg.args as [any]) });

    } else if (msg.type === "DialogueContext.dispose") {
      const ctx = ptrMap.get(msg.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.dispose() });

    }
    throw Error("unknown message type")

  } catch (err: any) {
    postMessage({ id, error: `${err.message}\n${err.stack}` });
  }
}));
