defmodule Nitro.Live.Examples.RimShop.CatalogPage do
  @moduledoc """
  Rim catalog with facet filters (brand/size/color) on the left, each facet
  value showing how many currently-matching results carry it. Facet counts
  are computed against every OTHER selected facet group but not the group
  being displayed, so toggling a value never hides its own siblings -- see
  `Nitro.Live.Examples.RimShop.Catalog.facet_counts/3`.

  Selection is OR within one facet group (checking "Black" and "Silver"
  under Color shows either) and AND across groups (Brand + Size + Color
  filters all apply together). Authored with `~H` throughout, including a
  private function component (`facet_section/1`) shared by all three facet
  groups.

  One of two real, separately-URLed pages (see `Nitro.Live.Examples.RimShop.ProductPage`
  and `Routes`/`Page`/`Cx` for how the path gets here). A result is an
  `<a href="/rim-shop/{id}">` wired as a `Nitro.Live.Nav` live-navigate
  link -- clicking it stays on the same WebSocket connection/process (no
  reload, no reconnect: `Page.event/1` intercepts it, mounts `ProductPage`
  under the same root id, and patches in place), while right-click/open in
  a new tab/no-JS still work off the real `href`. Filters here are still
  NOT preserved across a trip to a product and back -- `Page` always does
  a fresh `Runtime.mount/2` for whichever page a path resolves to, live-nav
  or not (no session id threaded through this demo -- see `Page`), unlike
  the `simple/` examples' reconnect-persistence feature.
  """

  use Nitro.Live
  alias Nitro.Live.{Socket, Nav}
  alias Nitro.Live.Examples.RimShop.{Catalog, Page}

  @empty_filters %{brand: MapSet.new(), size: MapSet.new(), color: MapSet.new()}

  @impl true
  def mount(_params, socket) do
    socket
    |> Socket.assign(:filters, @empty_filters)
    |> assign_results()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rim-shop">
      <aside class="facets">
        {facet_section(%{
          title: "Brand",
          group: :brand,
          live_id: @live_id,
          selected: @filters.brand,
          counts: Catalog.facet_counts(Catalog.all(), @filters, :brand)
        })}
        {facet_section(%{
          title: "Size",
          group: :size,
          live_id: @live_id,
          selected: @filters.size,
          counts: Catalog.facet_counts(Catalog.all(), @filters, :size)
        })}
        {facet_section(%{
          title: "Color",
          group: :color,
          live_id: @live_id,
          selected: @filters.color,
          counts: Catalog.facet_counts(Catalog.all(), @filters, :color)
        })}
        <button :if={@has_filters} postback={live_event(@live_id, :clear_filters)} delegate={Nitro.Live.Dispatcher} class="clear">Clear filters</button>
      </aside>
      <main class="results">
        <p class="count">{length(@results)} rim(s)</p>
        <ul>
          <li :for={item <- @results} class="rim">
            <a
              class="rim-link"
              href={"/rim-shop/" <> item.id}
              postback={Nav.live_navigate(@live_id, "/rim-shop/" <> item.id)}
              delegate={Page}
            >
              <span class="name">{item.brand} {item.name}</span>
              <span class="spec">{item.size} in - {item.color}</span>
              <span class="price">${item.price}</span>
            </a>
          </li>
        </ul>
      </main>
    </div>
    """
  end

  defp facet_section(assigns) do
    ~H"""
    <div class="facet-group">
      <h3>{@title}</h3>
      <ul>
        <li :for={{value, count} <- @counts}>
          <button
            class={facet_class(@selected, value)}
            postback={live_event(@live_id, {:toggle_facet, @group, value})}
            delegate={Nitro.Live.Dispatcher}
          >{facet_label(@group, value)} ({count})</button>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def handle_event({:toggle_facet, group, value}, _params, socket) do
    filters = Map.update!(socket.assigns.filters, group, &toggle_value(&1, value))
    socket |> Socket.assign(:filters, filters) |> assign_results()
  end

  def handle_event(:clear_filters, _params, socket) do
    socket |> Socket.assign(:filters, @empty_filters) |> assign_results()
  end

  defp toggle_value(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp assign_results(socket) do
    filters = socket.assigns.filters
    results = Catalog.filter(Catalog.all(), filters)
    has_filters = Enum.any?(filters, fn {_group, values} -> MapSet.size(values) > 0 end)
    Socket.assign(socket, %{results: results, has_filters: has_filters})
  end

  defp facet_class(selected, value) do
    if MapSet.member?(selected, value), do: "facet-value selected", else: "facet-value"
  end

  defp facet_label(:size, value), do: "#{value} in"
  defp facet_label(_group, value), do: to_string(value)
end
