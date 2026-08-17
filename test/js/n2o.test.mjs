import { test } from "node:test";
import assert from "node:assert/strict";
import { JSDOM } from "jsdom";
import fs from "node:fs";
import url from "node:url";

// priv/static/vendor/n2o/n2o.js is a plain (non-module) script relying on
// globals, not an ES module like nitro-live.js -- exercised here by
// actually running it as a <script> tag in jsdom (runScripts: "dangerously"),
// the same way a real browser loads it from priv/static/live.htm, rather
// than trying to import/parse it as a module.
function loadN2O({ wsPath, port } = {}) {
  const n2oSource = fs.readFileSync(
    url.fileURLToPath(new URL("../../priv/static/vendor/n2o/n2o.js", import.meta.url)),
    "utf8",
  );

  const dom = new JSDOM(
    `<!doctype html><body>
      <script>
        window.__bulletUrls = [];
        function bullet(u) { window.__bulletUrls.push(u); return { onmessage: null, onopen: null, onclose: null, send: function () {} }; }
        function next() {}
        window.port = ${JSON.stringify(port ?? "")};
      </script>
      <script>${n2oSource}</script>
      ${wsPath !== undefined ? `<script>wsPath = ${JSON.stringify(wsPath)};</script>` : ""}
    </body>`,
    { url: "http://localhost/", runScripts: "dangerously" },
  );

  return dom;
}

test("wsPath defaults to /ws, matching upstream n2o.js's own hardcoded value", () => {
  const dom = loadN2O();
  dom.window.N2O_start();
  assert.equal(dom.window.__bulletUrls.length, 1);
  assert.match(dom.window.__bulletUrls[0], /^ws:\/\/localhost\/ws/);
});

test("setting wsPath before N2O_start() changes the WebSocket connect path", () => {
  const dom = loadN2O({ wsPath: "/live-ws" });
  dom.window.N2O_start();
  assert.equal(dom.window.__bulletUrls.length, 1);
  assert.match(dom.window.__bulletUrls[0], /^ws:\/\/localhost\/live-ws/);
  assert.doesNotMatch(dom.window.__bulletUrls[0], /\/ws\//);
});

test("wsPath is used alongside host/port/querystring, not instead of them", () => {
  const dom = loadN2O({ wsPath: "/custom", port: "4000" });
  dom.window.N2O_start();
  assert.equal(dom.window.__bulletUrls[0], "ws://localhost:4000/custom/");
});
