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
own root Live view with its own mount/URL. A result is a plain
`<a href="/rim-shop/r7">`, not a postback -- clicking it is a real browser
navigation (new HTTP request, new WS connection), and loading
`/rim-shop/r7` directly (typed in, refreshed, bookmarked) mounts
`ProductPage` with that id server-side, the same as clicking would have.
That means facet selections do NOT survive a trip to a product and back
(no session id is threaded through this demo's `Runtime.mount/2`) --
an honest trade-off of real page navigation over the single-process,
assign-switching approach an earlier version of this example used.

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

