# Nitro.Live TODO

Gaps found using the prototype for real (rim_shop and friends), not from
reading the code. Same format as before: unchecked = not started, check
off with a `_Done: ..._` note when it's fixed.

## Missing features

- [x] No form support -- no change-tracking input bindings (Phoenix's
      `phx-change`/`phx-submit` equivalent), so a form with several fields
      either needs one postback per field or a hand-rolled way to collect
      values client-side before sending a postback. Nothing in
      `Nitro.Live` helped with this before.
      _Done: turned out nitro already has the whole mechanism, just never
      exposed at the Nitro.Live layer -- `action_event.erl`'s `data/2`
      generates a client-side `querySource(id)` call for every id in an
      element's own `source:` list, and `nitro_n2o.erl`'s `render_ev/4`
      `erlang:put/2`s each collected value into the process dictionary
      *before* `Module:event/1` runs. New `Nitro.Live.Form` wraps just the
      read side (`value/1`, `values/1`, thin `Process.get/1` wrappers) and
      adds `live_change/4` for per-keystroke tracking, which no nitro
      element supports on its own (every element hardcodes `click` for its
      *own* postback) -- it works by building an `#event{}` value for the
      field's own generic `actions:` field instead, which every element
      record carries and `wf_render_elements:render_element/1` wires
      unconditionally at render time, regardless of element type. Verified
      at the wire-JS level (`test/nitro/live/form_test.exs`) and for real
      in a browser: `Nitro.Live.Examples.Simple.ContactForm`, embedded in
      `Dashboard`, has a Save button collecting two fields via `source:`
      and a filter input re-rendering the list on every keystroke via
      `live_change/4` -- both clicked/typed into for real, focus preserved
      on the filter input the same way the existing textbox test proves.
- [x] No PubSub -- no way for one connection's event to push an update
      into other connections' rendered state (Phoenix.PubSub's job). Every
      example so far was single-connection; nothing broadcast across
      sockets/processes.
      _Done: new `Nitro.Live.PubSub` (a plain `Registry`, `keys: :duplicate`
      -- one entry per `{topic, subscriber}`, `Registry.dispatch/3` +
      `send/2` to reach every subscribed pid) plus `Nitro.Live.PubSub.Protocol`,
      a new N2O protocol module (same `info/3` contract as `n2o_heart`/
      `nitro_n2o`) that recognizes the `{:nitro_live_broadcast, topic, msg}`
      messages `broadcast/2` sends and needs adding to
      `Application.put_env(:n2o, :protocols, [...])` to have any effect
      (see `Simple.Server`) -- cowboy only calls `websocket_info/2` for an
      arbitrary Erlang message sent to a connection process, and N2O only
      routes that through whichever protocol modules are configured.
      `Nitro.Live.Runtime.dispatch_info/2` mirrors `dispatch/3` (same
      change-tracking + crash isolation) but for a new *optional*
      `handle_info/2` callback instead of `handle_event/3` -- added to the
      `Nitro.Live` behaviour as `@optional_callbacks`, same treatment as
      `update/2`. A subscribing module never updates its own assigns in
      `handle_event/3`, only broadcasts; the actual state change happens
      uniformly in `handle_info/2` for every subscriber, including the one
      that triggered it.

      One real, deliberate gap, documented in `PubSub`'s own moduledoc: no
      "give me current state on join" -- a connection that subscribes
      after a broadcast already happened never sees it (same limitation
      Phoenix.PubSub itself has; a real app pairs it with a separate state
      store or Presence for that, out of scope here). Also caught and
      fixed a real bug before it could bite: `Registry`'s `:duplicate`
      keys allow the same process to register a key more than once, so
      two different ids on one connection subscribing to the same topic
      would otherwise make `broadcast/2` deliver -- and `dispatch_info/2`
      run -- twice per id per broadcast; `subscribe/2` now registers the
      underlying `Registry` key at most once per `{process, topic}`
      regardless of how many ids subscribe to it.

      Verified across two real, separate Erlang processes at the wire-JS
      level (`test/nitro/live/pub_sub_test.exs`, including the
      double-registration fix specifically) and for real with two actual
      browser tabs open to `Nitro.Live.Examples.Simple.SharedCounter`
      (embedded in `Dashboard`): clicked "+1" in tab B, watched tab A's
      count update to match with zero interaction in tab A, confirmed
      everything else on tab A's page (toggle states, dashboard render
      count) stayed untouched (the patch was scoped to just
      `SharedCounter`'s own subtree), then clicked in tab A and confirmed
      tab B updated too -- both directions, no console errors either way.
- [x] No live navigation -- no `live_patch`/`live_redirect` equivalent
      (client-side URL change + targeted re-render without a full page
      reload/reconnect). `rim_shop`'s `CatalogPage <-> ProductPage` did
      real multi-page navigation via plain `<a href>` (full reload, fresh
      mount) specifically *because* there was no lighter-weight alternative.
      _Done: new `Nitro.Live.Nav` -- a live-navigating link is a real
      `<a href="...">` (right-click/new-tab/no-JS still work) that also
      carries a postback (`Nav.live_navigate/2`); the page module
      intercepts it (`Nav.path/1`) before falling through to
      `Dispatcher.event/1`, mounts the new page under the *same* root id
      on the *same* WebSocket connection, and `Nav.push_navigate/3`
      patches in place while also updating the address bar via
      `history.pushState` -- no reload, no reconnect. `RimShop.Page`/
      `CatalogPage`/`ProductPage` now use it instead of plain `<a href>`;
      `Routes.route/1` was generalized to parse both the real WS-connect
      path (`/ws/rim-shop/r1`) and a live-navigate path (`/rim-shop/r1`,
      no `/ws` prefix) with one function. One real, deliberate gap: the
      browser's own back/forward (`popstate`) has no network request to
      intercept, and reconstructing a validly-pickled postback entirely
      client-side would mean reimplementing Erlang term-to-binary + zlib
      in JS from scratch -- out of scope, so `nitro-live.js` does a real
      reload on `popstate` instead. Correct (right content for the URL),
      just not live for that one case.

      Verified at the wire-JS level (`test/nitro/live/rim_shop_test.exs`)
      and for real in a browser: clicked a catalog result, confirmed via
      `list_network_requests` that NO new document request was made (only
      the original page load), confirmed via the console log that the
      exact same `WS Connect` fired only once across the whole session and
      that `history.pushState({}, "", "/rim-shop/r7");` executed alongside
      the patch, clicked "back to results" the same way, then used a real
      browser back button and confirmed THAT correctly triggers a fresh
      document request (the documented `popstate` fallback) landing on the
      right content.

## `~H` compiler gaps

- [x] No `<script>`/`<style>` raw-text parsing -- the tag parser tries to
      parse their contents as template nodes instead of raw text, so
      `<script>` tags with `<`/`{` in them break. Already documented as a
      known limitation in `Nitro.Live.HTML.Compiler`'s moduledoc; listing
      it here too since it was a real, not just theoretical, thing that
      got hit.
      _Done: `<script>`/`<style>` are now raw-text elements, same as real
      HTML5 -- everything up to the literal `</script>`/`</style>` is one
      unescaped, unparsed text node (`take_raw_text/2`), no nested-tag
      parsing, no `{expr}` interpolation attempted inside them at all.
      Rendered via `NITRO.literal(html_encode: false)` (nitro's own
      `#literal.html_encode` field, already there, just never set to
      `false` from `~H` before) so the content reaches the DOM
      byte-for-byte instead of getting HTML-entity-escaped like ordinary
      text. Verified with 4 new tests in `test/nitro/live/html_test.exs`
      (verbatim `<script>`/`<style>` content including `<`/`{`/`}`/`&&`,
      an ordinary tag right after still interpolating/escaping normally,
      and a clear compile error for an unterminated `<script>`).

      Also checked something real HEEx users hit and this project hadn't
      run into yet: a `<script>` this module correctly compiles and
      renders still does NOT execute when it arrives via `push_patch/2` --
      confirmed for real against a running server/browser (`NitroLive.patch/2`
      with a script+style payload): the `<style>` took effect immediately,
      the `<script>` landed in the DOM completely inert. Not a bug -- standard
      browser behavior for anything inserted via `innerHTML` (which is how
      `parse/1`/morphdom build the tree being patched in), the same
      limitation Phoenix LiveView itself documents for `phx-update`-patched
      script tags. Only a `<script>` present in the very first
      server-rendered page (before any WebSocket connects) runs normally.
      Documented in the compiler's moduledoc rather than silently
      surprising anyone.
- [x] No `data-*`-style hyphenated attributes -- nitro records don't have
      matching field atoms for hyphenated names, so `data-foo={...}` failed
      to compile.
      _Done: `Nitro.Live.HTML.Compiler` routes any `data-*` attribute (both
      `data-foo="literal"` and `data-foo={expr}`, including bare `data-foo`
      with no value) into the element's generic `data_fields` field instead
      of trying to set it as a direct record keyword key -- every nitro
      element record already carries `data_fields` (a list of `{binary,
      value}` pairs the element's own renderer, e.g. element_button.erl,
      appends onto its normal HTML attributes via `wf_tags:display_property/1`),
      it just wasn't being used from `~H`. `aria-*` and other non-`data-`
      hyphenated names are unaffected -- still routed as a direct keyword
      key (and still fail, same as before) since nitro has its own separate
      `aria_states` mechanism for `aria-*` with a different expected shape,
      not investigated here. Verified with a new test in
      `test/nitro/live/html_test.exs` covering string, expr, and bare
      (valueless) `data-*` attributes.
