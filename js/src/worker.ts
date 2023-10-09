import { DialogueContext, makeDialogueContext } from ".";


const ptrMap = new Map<number, DialogueContext>();

window.onmessage = (async (msg) => {
  const id = msg.data.id;

  try {
    if (msg.data.type === "makeDialogueContext") {
      const newCtx = await makeDialogueContext(...msg.data.args as [any, any]);
      ptrMap.set(id, newCtx);
      postMessage({ id, ptr: id });

    } else if (msg.data.type === "DialogueContext.step") {
      const ctx = ptrMap.get(msg.data.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.step() });

    } else if (msg.data.type === "DialogueContext.reset") {
      const ctx = ptrMap.get(msg.data.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.reset() });

    } else if (msg.data.type === "DialogueContext.reply") {
      const ctx = ptrMap.get(msg.data.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.reply(...msg.data.args as [any]) });

    } else if (msg.data.type === "DialogueContext.dispose") {
      const ctx = ptrMap.get(msg.data.ptr);
      if (!ctx) throw Error("no such pointer");
      postMessage({ id, result: ctx.dispose() });

    }
    throw Error("unknown message type")

  } catch (err: any) {
    postMessage({ id, error: `${err.message}\n${err.stack}` });
  }
});
