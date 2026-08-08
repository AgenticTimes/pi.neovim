// tests/fake_pi.mjs — 伪 pi RPC server（测试双）
// 用法: node tests/fake_pi.mjs [scenario.json]
// scenario: { "<commandType>": [ {json模板}, ... ] }，模板内 %ID%/%CMD% 会被替换。
import fs from "node:fs";

const scenario = process.argv[2]
  ? JSON.parse(fs.readFileSync(process.argv[2], "utf8"))
  : null;

const defaultScenario = {
  get_state: [
    { type: "response", id: "%ID%", command: "get_state", success: true, data: {
      model: { provider: "fake", id: "fake-model" },
      thinkingLevel: "low",
      isStreaming: false,
      isCompacting: false,
      steeringMode: "all",
      followUpMode: "all",
      sessionId: "fake-session",
      sessionName: "fake",
      autoCompactionEnabled: true,
      messageCount: 0,
      pendingMessageCount: 0,
    } },
  ],
  get_commands: [
    { type: "response", id: "%ID%", command: "get_commands", success: true, data: [] },
  ],
  get_messages: [
    { type: "response", id: "%ID%", command: "get_messages", success: true, data: [] },
  ],
  prompt: [
    { type: "response", id: "%ID%", command: "prompt", success: true },
    { type: "agent_start" },
    { type: "message_start", message: { role: "assistant",
      content: [{ type: "text", text: "hello from fake pi" }] } },
    { type: "message_end", message: { role: "assistant",
      content: [{ type: "text", text: "hello from fake pi" }] } },
    { type: "agent_end", messages: [], willRetry: false },
  ],
  abort: [
    { type: "response", id: "%ID%", command: "abort", success: true },
  ],
};

const map = scenario ?? defaultScenario;
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.resume(); // 确保管道 stdin 立即进入流动模式（避免 Node 时序问题）
process.stdin.on("data", (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, i).trim();
    buf = buf.slice(i + 1);
    if (!line) continue;
    let cmd;
    try { cmd = JSON.parse(line); } catch { continue; }
    const templates = map[cmd.type];
    if (!templates) continue;
    for (const tpl of templates) {
      const out = JSON.stringify(tpl)
        .replaceAll("%ID%", cmd.id ?? "none")
        .replaceAll("%CMD%", cmd.type);
      process.stdout.write(out + "\n");
    }
  }
});
