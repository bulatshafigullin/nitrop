# Facet-filtered rim catalog and a real, separately-URLed product detail
# page -- mount each root Live view directly (bypassing the real N2O/cowboy
# request cycle Routes/Cx/Page use for actual path-based routing) and
# render them, plus a standalone check of the path -> page parsing itself.
# Run: mix run scripts/rim_shop_demo.exs

alias Nitro.Live.Runtime
alias Nitro.Live.Examples.RimShop.{Catalog, CatalogPage, ProductPage, Routes}

html = fn tree -> tree |> :wf_render.render() |> IO.iodata_to_binary() end

IO.puts("== path -> page routing (Routes.route/1, no real cowboy request needed) ==")
IO.inspect(Routes.route("/ws"), label: ~c"/ws")
IO.inspect(Routes.route("/ws/rim-shop"), label: ~c"/ws/rim-shop")
IO.inspect(Routes.route("/ws/rim-shop/r7"), label: ~c"/ws/rim-shop/r7")

IO.puts("\n== CatalogPage: mount + initial render (all #{length(Catalog.all())} rims, each a real <a href> link) ==")
Runtime.mount(CatalogPage, "catalog-root")
IO.puts(html.(Runtime.render_root("catalog-root")))

IO.puts("\n== select Brand=BBS ==")
{:changed, tree1} = Runtime.dispatch("catalog-root", {:toggle_facet, :brand, "BBS"}, %{})
IO.puts(html.(tree1))

IO.puts("\n== ProductPage: mount with item_id \"r1\" (what Page.event(:init) does for /rim-shop/r1) ==")
Runtime.mount(ProductPage, "product-root", %{item_id: "r1"})
IO.puts(html.(Runtime.render_root("product-root")))

IO.puts(
  "\nNote: CatalogPage and ProductPage are two separate, independently-mounted root " <>
    "processes/sockets here -- unlike the earlier single-view version of this demo, " <>
    "navigating between them for real is a full browser navigation (see Page/Routes/Cx), " <>
    "so CatalogPage's BBS filter above is NOT carried over to ProductPage or back."
)
