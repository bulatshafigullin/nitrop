NITRO: Nitrogen Web Framework
=============================

[![Actions Status](https://github.com/synrc/nitro/workflows/mix/badge.svg)](https://github.com/synrc/nitro/actions)
[![Hex pm](https://img.shields.io/hexpm/v/nitro.svg?style=flat)](https://hex.pm/packages/nitro)

Features
--------

* Full HTML5 and SVG Support
* Support for N2O Erlang WebSocket Application Server
* Native Erlang way for UI/UX controls as HTML/JS/CSS components
* Tag Inheritance
* Polymorphic Tuples
* Compact size (2500 LOC)
* As fast as DTL and EEX
* Elixir, MIX and HEX support
* Custom Tags, ARIA, Web Components

Credits
-------

* Maxim Sokhatsky — Adaptation
* Rusty Klophaus — Original Author
* Jesse Gumm — Nitrogen Maintainer

Nitro.Live prototype
--------------------

Key features:

* Phoenix.LiveView-style `mount/render/handle_event` lifecycle on top of
  nitro's own existing record/render pipeline -- no parallel framework
* Real DOM diff/patch via a vendored `morphdom` (the same fork Phoenix
  LiveView depends on), not a full `outerHTML` replace -- preserves focus
  and in-progress typing on fields a patch doesn't touch
* HEEx-flavored `~H` templates (`Nitro.Live.HTML`) that compile to the
  exact same record tree hand-written `NITRO.panel(...)` calls do, and
  interoperate freely with them -- including `:if`/`:for` directives,
  `data-*` attributes, and `<script>`/`<style>` raw-text parsing
* Nested components (`Runtime.component/3`) with automatic GC of children
  a parent stops embedding
* Crash isolation per event -- a bad `handle_event/3` can't corrupt live
  state or take the connection down
* Reconnect-aware state persistence -- an N2O session id survives a page
  refresh instead of remounting from scratch
* Forms (`Nitro.Live.Form`) -- `phx-submit`/`phx-change` equivalents,
  built on nitro's own pre-existing `source:`/`querySource` wiring
* PubSub (`Nitro.Live.PubSub`) -- cross-connection broadcast, backed by a
  plain `Registry`, no separate pub/sub server
* Live navigation (`Nitro.Live.Nav`) -- a `live_patch`/`live_redirect`
  equivalent: URL and content update on the same WebSocket connection, no
  reload, no reconnect
* A real multi-page routing example (`rim_shop`) -- genuinely separate
  pages/URLs, not one single-page-app process switching views

`lib/nitro/live/` adds a Phoenix.LiveView-style `mount/render/handle_event`
lifecycle on top of nitro's own record/render pipeline: server-held state
(`Nitro.Live.Socket`), nested components (`Runtime.component/3`, with GC of
components no longer embedded by their parent), crash isolation per event,
and reconnect-aware state persistence (an N2O session id ties a page refresh
back to prior state instead of remounting). DOM updates go out as real
diffs/patches via a vendored `morphdom` (`priv/static/vendor/morphdom/`,
the same fork Phoenix LiveView depends on) driven by
`priv/static/nitro-live.js`, instead of a full `outerHTML` replace --
preserving focus and in-progress typing on fields the patch doesn't touch.
See `TODO.md` for what's still open.

`render/1` can build that record tree either by calling `NITRO.panel(...)`
etc. directly, or with an HEEx-flavored `~H` sigil (`lib/nitro/live/html.ex`,
grammar and limitations documented in `Nitro.Live.HTML.Compiler`'s
moduledoc) -- both compile to the exact same tree and interoperate freely
(a `~H` template can embed a hand-built one and vice versa):

    def render(assigns) do
      ~H"""
      <div class="counter">
        <span>Count: {@count}</span>
        <button postback={live_event(@live_id, :inc)} delegate={Nitro.Live.Dispatcher}>+</button>
      </div>
      """
    end

`Nitro.Live.Form` adds Phoenix's `phx-submit`/`phx-change` equivalents on
top of nitro's own pre-existing (but previously unexposed) `source:`/
`querySource` wiring: `source: [...]` on any postback-carrying element
collects other fields' current values into one postback (`Form.values/1`
reads them back in `handle_event/3`), and `live_change/4` fires a postback
on a field's own keystrokes, no submit button needed. See its moduledoc
for how, and `Nitro.Live.Examples.Simple.ContactForm` for both in one page.

`Nitro.Live.PubSub` adds Phoenix.PubSub's job: pushing an update into
every OTHER connection watching a topic, not just the one whose event
triggered it. `subscribe/2` in `mount/2`, `broadcast/2` from
`handle_event/3` (a subscribing module updates its own assigns in the new
optional `handle_info/2` callback instead, uniformly for every
subscriber including itself), and `Nitro.Live.PubSub.Protocol` -- a new
N2O protocol module, added to `Application.put_env(:n2o, :protocols, [...])`
-- delivers it: cowboy's `websocket_info/2` is the hook for a server to
push an unsolicited frame to a client at any time, not just in response
to that client's own request. See its moduledoc for the mechanism (a
plain `Registry`, no separate pub/sub server) and what it deliberately
doesn't do (no state-on-join), and
`Nitro.Live.Examples.Simple.SharedCounter` for it live: open the same
page in two tabs, `+1` in one, watch the other update with zero
interaction.

Demo modules live under `lib/nitro/live/examples/simple/`. To run the real
Cowboy + N2O server they wire up:

    mix deps.get
    mix run scripts/run_server.exs

then open `http://localhost:8080/`. `scripts/live_demo.exs`,
`scripts/component_demo.exs`, `scripts/lifecycle_demo.exs` and
`scripts/heex_demo.exs` exercise the same lifecycle without a browser
(`mix run scripts/<name>.exs`).

The same counter/toggle feature is also built three ways side by side, to
compare the approaches directly:

* `Nitro.Live.Examples.Simple.PureNitroCounter` -- plain nitro, no Nitro.Live at
  all: its own `event/1`, state via `nitro:state/1,2`, every event resends
  the whole node as a full `outerHTML` replace via `nitro:update/2`.
* `Nitro.Live.Examples.Simple.PureLivePage` -- all Nitro.Live: `mount/render/handle_event`,
  `dispatch/3`'s change tracking, scoped `push_patch/2`.
* `Nitro.Live.Examples.Simple.MixedPage` -- a classic nitro page (own `event/1`,
  own `nitro:state/1,2`) that embeds one Nitro.Live component as an island
  via `Runtime.component/3`, so its own postbacks and the island's postbacks
  are patched completely independently on the same page.

`mix run scripts/approaches_demo.exs` runs all three and prints the actual
wire JS each one sends per event.

Tests: `mix test` (Elixir/ExUnit, `test/nitro/live/`) and `npm test`
(the client-side patch logic, jsdom, `test/js/`).

`mix run scripts/benchmark.exs` compares plain nitro (rebuild + render the
whole page on every event, no scoping below the raw record layer) against
Nitro.Live (`dispatch/3` + scoped `push_patch/2`, re-rendering and sending
only the one component subtree that changed) at 1/10/50 nested components --
both per-event latency and bytes rendered per event.

### rim_shop -- a less trivial, real multi-page example

`lib/nitro/live/examples/rim_shop/` is a rim catalog (`Catalog`, 24 static
items) with facet filters -- brand/size/color -- in a left `<aside>`, each
facet value showing how many currently-matching results carry it. Facet
counts are computed against every OTHER selected facet group but not the
group being displayed, so picking a value never hides its own siblings
(the standard faceted-search UX, same as Elasticsearch/Algolia
aggregations -- see `Catalog.facet_counts/3`). Selection is OR within one
group, AND across groups.

Two genuinely separate pages, not one Live view switching what it shows:
`CatalogPage` (`/rim-shop`) and `ProductPage` (`/rim-shop/:id`), each its
own root Live view with its own mount/URL. A result is a real
`<a href="/rim-shop/r7">` -- open it in a new tab, bookmark it, load it
directly, and `ProductPage` mounts with that id server-side, same as
clicking would -- but the click itself is a `Nitro.Live.Nav`
live-navigate: same WebSocket connection the whole time, no reload, no
reconnect (see the `Nitro.Live.Nav` section below). Facet selections
still do NOT survive a trip to a product and back (no session id is
threaded through this demo's `Runtime.mount/2`) -- an honest trade-off
that has nothing to do with live-vs-full-reload navigation; it's the
same "no persistence in this demo" limitation either way.

Making this work needed one real piece of plumbing: N2O's own cx-builder
(`n2o_proto:cx/2`) never reads the request path off the cowboy `Req`, even
though `n2o.js`'s own WS connect URL is built from
`location.pathname + location.search` -- so the exact page path a browser
is on is already sitting on the very `Req` cowboy hands to the websocket
upgrade, just unused. `Cx.cx/2` wraps `n2o_proto:cx/2` to also capture it
(`Application.put_env(:n2o, :cx, {Cx, :cx})`, see `RimShop.Server`), and
`Routes.init/2` parses it (`Routes.route/1`, pure and unit-tested on its
own) to decide `CatalogPage` vs `ProductPage` -- `cx.module` itself still
has to stay a single atom (nitro_n2o.erl calls `Module:event(Event)`
directly), so the parsed route goes through `cx.params` instead and
`Page.event(:init)` reads it back out to decide what to mount.

    mix run scripts/rim_shop_demo.exs        # no browser, prints HTML + path-routing per step
    mix run scripts/run_rim_shop_server.exs  # then open http://localhost:8081/rim-shop

Don't run this alongside the `simple/` server in the same node -- see
`RimShop.Server`'s moduledoc for why. Tests: `test/nitro/live/rim_shop_test.exs`.

`Nitro.Live.Nav` (`live_patch`/`live_redirect`-equivalent client-side
navigation) is what makes `CatalogPage <-> ProductPage` clicks skip the
reload: a live-navigating link is a real `<a href>` that also carries a
postback, a page's `event/1` intercepts it (`Nav.path/1`) before falling
through to `Dispatcher.event/1`, mounts the new page under the same root
id on the same connection, and `Nav.push_navigate/3` patches in place
while updating the address bar via `history.pushState`. Browser
back/forward (`popstate`) is the one deliberate exception -- reconstructing
a validly-pickled postback entirely client-side would mean reimplementing
Erlang term-to-binary + zlib in JS, so `nitro-live.js` does a real reload
there instead: correct content for the URL, just not live for that one
case. See `Nitro.Live.Nav`'s moduledoc for the full picture and how to
wire a page up to it.

