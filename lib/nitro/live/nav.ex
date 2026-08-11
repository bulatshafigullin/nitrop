defmodule Nitro.Live.Nav do
  @moduledoc """
  Client-side navigation between root Live views without a full page
  reload/reconnect -- the `live_patch`/`live_redirect` equivalent. Same
  WebSocket connection, same process, the whole time: only
  `Runtime.mount/3` swaps which module is mounted under the page's root
  id, and `push_navigate/3` (instead of `Runtime.push_patch/2`) also
  updates the browser's address bar via `history.pushState` before
  applying the patch.

  Nothing here decides *which* module a path maps to -- that's still each
  app's own job (see `Nitro.Live.Examples.RimShop.Routes.route/1`, reused
  for both the real WS-connect-time path *and* live-navigate paths). This
  module only provides the mechanism: building the postback for a
  live-navigating link, recognizing one when it comes back, and applying
  the patch + history update together.

  ## Wiring it up

  A live-navigating link is a REAL `<a href="...">` (so right-click/open
  in a new tab/no-JS still works -- see `RimShop.Page`'s `event(:init)`,
  which already handles a direct load of any path correctly) that ALSO
  carries a postback:

      <a href={"/rim-shop/" <> id} postback={Nav.live_navigate(@live_id, "/rim-shop/" <> id)} delegate={RimShop.Page}>...</a>

  `delegate` has to be the PAGE module (not `Nitro.Live.Dispatcher`),
  because a live-navigate postback needs intercepting *before* the normal
  `Dispatcher.event/1` path -- the same reason `event(:init)` is handled
  by the page module directly instead of a component. In the page
  module's own `event/1`:

      def event(:init) do ... end

      def event(postback) do
        case Nav.path(postback) do
          {:ok, path} ->
            {module, params} = Routes.route(path)
            Runtime.mount(module, @root_id, params)
            Nav.push_navigate(@root_id, path, Runtime.render_root(@root_id))
            []

          :error ->
            Nitro.Live.Dispatcher.event(postback)
        end
      end

  ## What's NOT covered

  The browser's own back/forward buttons fire a `popstate` event with no
  network request at all -- nothing to intercept server-side, and
  reconstructing a *new*, validly-pickled postback entirely client-side
  (nitro's pickle format is `base64(term_to_binary({Data, timestamp}, [compressed]))`
  -- real Erlang External Term Format plus zlib, not something to
  hand-roll in vanilla JS for one feature) is out of scope here.
  `priv/static/nitro-live.js` instead does a real page reload on
  `popstate`, so back/forward are always *correct* (right content for the
  URL) even though they're not *live* the way a forward live-navigate
  click is.
  """

  @doc "Builds the postback for a live-navigating link/button; see this module's moduledoc for the intercept side."
  def live_navigate(live_id, path), do: Nitro.Live.live_event(live_id, {:__live_navigate__, path})

  @doc "Extracts the target path from a postback built by `live_navigate/2`, or `:error` for anything else."
  def path({:live_event, _id, {:__live_navigate__, path}, _params}), do: {:ok, path}
  def path(_), do: :error

  @doc """
  Like `Nitro.Live.Runtime.push_patch/2`, but also updates the browser's
  address bar via `history.pushState` (no reload, no reconnect) -- the
  whole point of live navigation over a patch-in-place, which never
  touches the URL. `path` is `nitro:jse/1`-escaped the same way
  `push_patch/2` escapes patched HTML, since it ends up inside a
  double-quoted JS string literal too.
  """
  def push_navigate(id, path, tree) do
    Nitro.Live.Runtime.push_patch(id, tree)
    :nitro.wire(:nitro.f(~c'history.pushState({}, "", "~s");', [:nitro.jse(path)]))
  end
end
