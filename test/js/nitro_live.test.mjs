import { test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";

async function withDom(initialHtml) {
  const dom = new JSDOM(`<!doctype html><body>${initialHtml}</body>`, {
    url: "http://localhost/",
  });
  global.window = dom.window;
  global.document = dom.window.document;
  global.HTMLElement = dom.window.HTMLElement;
  global.customElements = dom.window.customElements;
  global.Node = dom.window.Node;
  global.getComputedStyle = dom.window.getComputedStyle;

  // cache-bust so re-imports across tests see fresh module state under --test's isolation
  const mod = await import(`../../priv/static/nitro-live.js?t=${Date.now()}-${Math.random()}`);
  return { dom, NitroLive: mod.default };
}

test("patch updates changed text without touching unrelated node identity", async () => {
  const { dom, NitroLive } = await withDom(
    `<div id="app"><span id="count">Count: 0</span><span id="static">unchanged</span></div>`,
  );
  const staticBefore = dom.window.document.getElementById("static");

  NitroLive.patch(
    "app",
    `<div id="app"><span id="count">Count: 1</span><span id="static">unchanged</span></div>`,
  );

  assert.equal(dom.window.document.getElementById("count").textContent, "Count: 1");
  assert.equal(
    dom.window.document.getElementById("static"),
    staticBefore,
    "unrelated node must be the same DOM object, not replaced -- proves this is a diff/patch, not outerHTML replace",
  );
});

test("patch preserves focus and in-progress typing on the focused input", async () => {
  const { dom, NitroLive } = await withDom(
    `<div id="app"><span id="count">Count: 0</span><input id="name" value="server-initial"></div>`,
  );
  const { document } = dom.window;
  const input = document.getElementById("name");
  input.focus();
  input.value = "user is typing this";
  input.setSelectionRange(4, 6);

  NitroLive.patch(
    "app",
    `<div id="app"><span id="count">Count: 1</span><input id="name" value="stale-server-value"></div>`,
  );

  assert.equal(document.getElementById("count").textContent, "Count: 1", "unrelated update still applied");
  assert.equal(document.activeElement, input, "focus preserved");
  assert.equal(input.value, "user is typing this", "focused input's in-progress value must not be clobbered by the server's stale value");
  assert.equal(input.selectionStart, 4);
  assert.equal(input.selectionEnd, 6);
});

test("patch applies the server value once the input loses focus", async () => {
  const { dom, NitroLive } = await withDom(
    `<div id="app"><input id="name" value="old"></div>`,
  );
  const { document } = dom.window;

  NitroLive.patch("app", `<div id="app"><input id="name" value="new"></div>`);

  assert.equal(document.getElementById("name").value, "new");
});

test("elements marked data-nitro-ignore are left untouched", async () => {
  const { dom, NitroLive } = await withDom(
    `<div id="app"><div id="widget" data-nitro-ignore data-thirdparty-state="mounted-by-js">original</div></div>`,
  );
  const { document } = dom.window;
  const widgetBefore = document.getElementById("widget");
  widgetBefore.textContent = "mutated by some third-party widget after mount";

  NitroLive.patch(
    "app",
    `<div id="app"><div id="widget" data-nitro-ignore>server thinks this is the content</div></div>`,
  );

  assert.equal(document.getElementById("widget"), widgetBefore);
  assert.equal(
    document.getElementById("widget").textContent,
    "mutated by some third-party widget after mount",
    "ignored subtree must not be overwritten by the server render",
  );
});

// This is the literal wire payload `Nitro.Live.Runtime.push_patch/2` emits
// (captured from `mix run scripts/live_demo.exs`, before `nitro:wire/1` wraps
// it in a `{var x=qi(...` ... no-op prefix -- N2O's client evaluates the raw
// JS string as-is). Evaluating it here proves the Elixir/Erlang side and this
// client module actually agree on a wire format, not just each half in
// isolation.
test("the exact JS string push_patch/2 generates applies correctly when evaluated", async () => {
  const { dom, NitroLive } = await withDom(
    `<div id="counter1"><div class="counter"><span id="count">Count: 0</span><button id="auto-1" type="button">+</button><button id="auto-2" type="button">-</button></div></div>`,
  );
  const { document } = dom.window;
  global.NitroLive = NitroLive; // matches window.NitroLive as seen by a real <script type="module"> page

  const serverWire =
    'NitroLive.patch("counter1", "<div id=\\"counter1\\"><div class=\\"counter\\"><span id=\\"count\\">Count: 1</span><button id=\\"auto-421500\\" type=\\"button\\">+</button><button id=\\"auto-421468\\" type=\\"button\\">-</button></div></div>");';

  (0, eval)(serverWire); // indirect eval: runs in global scope, exactly how N2O's client executes wire payloads

  assert.equal(document.getElementById("count").textContent, "Count: 1");
  assert.equal(document.getElementById("auto-421500").textContent, "+");
});
