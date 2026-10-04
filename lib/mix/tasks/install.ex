defmodule Mix.Tasks.DicEx.Install do
  @moduledoc """
  Copies the dicEx prebuilt assets into the host Phoenix application's
  `assets/vendor` and `assets/css` directories so they bundle into `app.js` /
  `app.css`, and prints the wiring snippet.

      mix dic_ex.install

  Phoenix 1.8+ only serves `app.js` / `app.css` from the bundle, so dicEx's
  assets must be imported rather than referenced via external `<script>` tags.
  Run this inside your Phoenix app after adding `:dic_ex` to your
  dependencies. Re-run it after upgrading dicEx so the vendored JS matches the
  component.

  Two bundles are copied: `dic_ex.min.js` (both engines, ~2.7 MB because it
  embeds Three.js and Rapier) and `dic_ex_2d.min.js` (2D engine only, a few
  KB). Import just one of them.
  """

  use Mix.Task

  @shortdoc "Installs dicEx assets into the host Phoenix app"

  @impl true
  def run(_args) do
    cwd = File.cwd!()
    vendor = Path.join(cwd, "assets/vendor")
    css_dir = Path.join(cwd, "assets/css")
    File.mkdir_p!(vendor)
    File.mkdir_p!(css_dir)

    copies = [
      {"dic_ex.min.js", Path.join(vendor, "dic_ex.min.js")},
      {"dic_ex_2d.min.js", Path.join(vendor, "dic_ex_2d.min.js")},
      {"dic_ex.css", Path.join(css_dir, "dic_ex.css")}
    ]

    for {file, dest} <- copies do
      src = Path.join([:code.priv_dir(:dic_ex), "static", file])

      if File.exists?(src) do
        File.cp!(src, dest)
        Mix.shell().info("[dicEx] copied #{file} -> #{Path.relative_to_cwd(dest)}")
      else
        Mix.shell().error("[dicEx] missing #{file} — run `mix dic_ex.build` in the package first")
      end
    end

    Mix.shell().info("""

    dicEx assets copied. Two manual steps to wire them into your bundle:

    1) Import the JS hook in assets/js/app.js (anywhere before LiveSocket):

        import "../vendor/dic_ex.min.js"     // 2D + 3D (~2.7 MB)
        // or, if every roller uses engine="2d":
        // import "../vendor/dic_ex_2d.min.js" // 2D only (a few KB)

        // then make sure the hook reaches LiveSocket:
        const hooks = { ...(window.DicExHooks || {}) }
        const liveSocket = new LiveSocket("/live", Socket, { hooks, params: {_csrf_token: csrfToken} })

    2) Import the styles in assets/css/app.css (after the tailwind import):

        @import "./dic_ex.css";

    Then drop the component into any LiveView:

        <.live_component module={DicExWeb.DiceRoller} id="roller" on_roll={self()} />

    and receive rolls in the host:

        def handle_info({:dic_ex_rolled, %{result: result}}, socket), do: ...
    """)
  end
end
