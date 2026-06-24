if Code.ensure_loaded?(Phoenix.LiveComponent) do
  defmodule DicExWeb.DiceRoller do
    @moduledoc """
    A self-contained LiveComponent that renders the pixel-art 3D dice roller.

    Drop it into any LiveView (inline or as a modal) and it manages its own state:
    the current expression, the quick dice tray, and the last roll result. The 3D
    animation is driven by the `DiceRoller` JavaScript hook which lives in
    `priv/static/dic_ex.min.js`.

    ## Usage

        # in your LiveView template (inline)
        <.live_component module={DicExWeb.DiceRoller} id="dice-roller" />

        # as a modal — wrap it however you like
        <.modal :if={@show_roller}>
          <.live_component module={DicExWeb.DiceRoller} id="dice-roller" />
        </.modal>

    ## Options

      * `default` — initial expression (default `"1d20"`).
      * `theme` — `"obsidian"` (default), `"arcane"` or `"dnd"`. Tunes the pixel palette.
      * `engine` — `"3d"` (default; Three.js + Rapier physics) or `"2d"` (canvas,
        no physics: the die tumbles in 2D and lands on the authoritative value).
        Both engines share the exact same Elixir roll; this only swaps the hook.
      * `rng` — RNG module for the rolls (default `nil` ⇒ `DicEx.RNG.Default`,
        reproducible via `:seed`). Pass `DicEx.RNG.Entropy` for cryptographic,
        non-replayable randomness. Applies to whichever engine is selected.
      * `on_roll` — a `pid` (or registered name) to notify of every roll via
        `send/2` with `{:dic_ex_rolled, %{result: result, component: id}}`.
        dragonEx uses this to feed the AI game master the structured outcome.
      * `autoplay` — if `true`, performs an initial roll on mount (default `false`).

    ## Receiving rolls (dragonEx integration)

        <.live_component module={DicExWeb.DiceRoller} id="roller"
          on_roll={self()} />

        def handle_info({:dic_ex_rolled, %{result: result}}, socket) do
          # result is a %DicEx.Result{}; feed its JSON map to the LLM
          DragonEx.GameMaster.register_roll(result)
          {:noreply, socket}
        end
    """

    use Phoenix.LiveComponent

    # The component is only defined when Phoenix LiveView is available so the
    # pure-rolling core stays usable without any web dependency.

    alias DicEx.{Result, Theme}

    defp quick_dice, do: ~w(d4 d6 d8 d10 d12 d20)

    # The LiveView hook name is what actually swaps the render engine. Both
    # hooks speak the same dic_ex:roll / dic_ex:settled contract, so the rest of
    # the component (state, roll logic, reveal) is identical for 2D and 3D.
    defp hook_name("2d"), do: "DiceRoller2D"
    defp hook_name(_), do: "DiceRoller"

    # Theme can be a built-in name or a custom palette map. We resolve it once
    # into the chrome CSS vars (inline) and the canvas palette (JSON for the JS
    # hooks), so hosts can skin the roller without touching the bundle.
    defp resolve_theme(theme) do
      palette = Theme.resolve(theme)
      name = if is_binary(theme) or is_atom(theme), do: to_string(theme), else: nil
      {palette, name}
    end

    defp style_vars(palette) do
      palette
      |> Theme.css_vars()
      |> Enum.map_join("; ", fn {k, v} -> "#{k}: #{v}" end)
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div
        id={@id}
        class={["dicex-roller", "dicex-engine-#{@engine}", @theme_class]}
        style={@style_vars}
        phx-hook={hook_name(@engine)}
        data-palette={@canvas_palette}
        phx-target={@myself}
      >
        <div
          class="dicex-stage"
          id={"#{@id}-stage"}
          data-dicex-stage
          phx-update="ignore"
        >
        </div>

        <div class="dicex-controls">
          <div class="dicex-tray">
            <button
              :for={d <- quick_dice()}
              type="button"
              class="dicex-die-btn"
              title={"añadir " <> d}
              phx-click="add-die"
              phx-target={@myself}
              phx-value-die={d}
            >
              {d}
            </button>
          </div>

          <form phx-submit="roll" phx-target={@myself} class="dicex-form">
            <input
              class="dicex-input"
              type="text"
              name="expression"
              value={@expression}
              placeholder="1d4+2d6, 2d20kh1+5, 8d6! ..."
              autocomplete="off"
            />
            <button type="button" class="dicex-clear-btn" phx-click="clear" phx-target={@myself}>
              limpiar
            </button>
            <button type="submit" class="dicex-roll-btn">Tirar</button>
          </form>
        </div>

        <div class="dicex-result" :if={@rolling}>
          <div class="dicex-total dicex-rolling-total">tirando…</div>
        </div>

        <div class="dicex-result" :if={not @rolling and @result}>
          <div class="dicex-total">{@result.total}</div>
          <div class="dicex-breakdown">
            <span :for={r <- breakdown(@result)} class={["dicex-pill", r.kept && "dicex-kept", !r.kept && "dicex-dropped"]}>
              {r.value}
            </span>
          </div>
          <div class="dicex-expression">{@result.expression}</div>
        </div>
      </div>
      """
    end

    @impl true
    def mount(socket) do
      {:ok,
       socket
       |> assign(:expression, "1d20")
       |> assign(:result, nil)
       |> assign(:pending_result, nil)
       |> assign(:rolling, false)
       |> assign_theme("obsidian")
       |> assign(:engine, "3d")
       |> assign(:rng, nil)
       |> assign(:on_roll, nil)
       |> assign(:autoplay, false)}
    end

    # Collapse a theme option into the three assigns the template needs:
    # the resolved palette, the optional built-in class name, and the JSON
    # canvas palette shipped to the JS hooks.
    defp assign_theme(socket, theme) do
      {palette, name} = resolve_theme(theme)

      socket
      |> assign(:theme, theme)
      |> assign(:theme_class, if(name, do: "dicex-theme-#{name}"))
      |> assign(:style_vars, style_vars(palette))
      |> assign(:canvas_palette, Jason.encode!(Theme.canvas_palette(palette)))
    end

    # Fallback only: if the dice never report settling (scene failed to init,
    # tab was backgrounded, ...) reveal anyway after a generous timeout. The
    # "dic_ex:settled" event is the primary, in-sync reveal path.
    @reveal_fallback 6000

    @impl true
    def update(%{reveal: result}, socket) do
      {:ok, maybe_reveal(socket, result)}
    end

    def update(%{id: id} = opts, socket) do
      socket =
        socket
        |> assign(:id, id)
        |> assign_theme(Map.get(opts, :theme, "obsidian"))
        |> assign(:engine, Map.get(opts, :engine, "3d"))
        |> assign(:rng, Map.get(opts, :rng))
        |> assign(:on_roll, Map.get(opts, :on_roll))
        |> assign(:autoplay, Map.get(opts, :autoplay, false))

      socket =
        case Map.fetch(opts, :default) do
          {:ok, default} -> assign(socket, :expression, default)
          :error -> socket
        end

      {:ok, socket}
    end

    # Tray buttons accumulate dice into the hand, so mixed pools like
    # "1d4+2d6" build up naturally (click d4, d6, d6). Repeated clicks on the
    # same plain trailing term increment its count instead of stacking terms.
    @impl true
    def handle_event("add-die", %{"die" => die}, socket) do
      {:noreply, assign(socket, :expression, append_die(socket.assigns.expression, die))}
    end

    def handle_event("clear", _params, socket) do
      {:noreply, assign(socket, :expression, "")}
    end

    # Primary reveal path: the JS hook reports that every die has finished its
    # settle animation, so we reveal the result exactly in sync with the dice.
    # The event name carries this component's id so several rollers can coexist
    # in the same LiveView without cross-firing each other's reveal.
    def handle_event("dic_ex:settled:" <> _id, _params, socket) do
      {:noreply, maybe_reveal(socket, socket.assigns[:pending_result])}
    end

    # Physics-truth (3D) reveal: the hook reports the face values that actually
    # landed up. We re-evaluate the expression with those values piped through
    # the deterministic RNG, so modifiers (kh/dl/explode…) are still applied and
    # the revealed result matches exactly what the player sees on the table.
    def handle_event("dic_ex:landed:" <> _id, %{"values" => values}, socket) do
      result = reroll_with(socket.assigns.expression, values)
      {:noreply, maybe_reveal(socket, result)}
    end

    def handle_event("roll", %{"expression" => expression}, socket) do
      perform_roll(expression, socket)
    end

    def handle_event("roll", _params, socket) do
      perform_roll(socket.assigns.expression, socket)
    end

    defp perform_roll(expression, socket) do
      case DicEx.roll_e(expression, roll_opts(socket.assigns[:rng])) do
        {:ok, result} ->
          # animation kicks off immediately; the result is revealed when the dice
          # report settling ("dic_ex:settled"), with a fallback timer as safety.
          id = socket.assigns.id

          Task.start(fn ->
            Process.sleep(@reveal_fallback)
            send_update(__MODULE__, %{id: id, reveal: result})
          end)

          {:noreply,
           socket
           |> assign(:rolling, true)
           |> assign(:result, nil)
           |> assign(:pending_result, result)
           |> push_roll(result)}

        {:error, reason} ->
          {:noreply, push_event(socket, error_event(socket.assigns.id), %{message: reason})}
      end
    end

    defp roll_opts(nil), do: []
    defp roll_opts(rng), do: [rng: rng]

    # Re-evaluates the expression forcing the supplied face values as the base
    # rolls (used by the physics-truth 3D engine so the result matches the
    # landed dice). Explodes that need more rolls than provided fall back to 1.
    defp reroll_with(expression, values) do
      DicEx.roll(expression, rng: {DicEx.RNG.Deterministic, values})
    end

    # Per-instance event names. `push_event/3` broadcasts to every hook on the
    # LiveView, so we suffix the roll/error channels with the component id and
    # each hook only listens for its own. (`dic_ex:theme` stays global — a theme
    # change should reach every roller on the page.)
    defp roll_event(id), do: "dic_ex:roll:#{id}"
    defp error_event(id), do: "dic_ex:error:#{id}"

    defp push_roll(socket, %Result{} = result) do
      push_event(socket, roll_event(socket.assigns.id), Result.to_roll_event(result))
    end

    # Reveal the pending result exactly once. Guards against the settle event
    # and the fallback timer both firing, and against a stale pending result.
    defp maybe_reveal(socket, nil), do: socket
    defp maybe_reveal(%{assigns: %{rolling: false}} = socket, _result), do: socket

    defp maybe_reveal(socket, result) do
      notify_host(socket, result)

      socket
      |> assign(:result, result)
      |> assign(:rolling, false)
      |> assign(:pending_result, nil)
    end

    @rolled_msg :dic_ex_rolled

    defp notify_host(socket, %Result{} = result) do
      case socket.assigns[:on_roll] do
        nil ->
          :ok

        target when is_pid(target) ->
          send(target, {@rolled_msg, %{result: result, component: socket.assigns.id}})

        name when is_atom(name) ->
          send(name, {@rolled_msg, %{result: result, component: socket.assigns.id}})
      end
    end

    defp append_die("", die), do: "1" <> die

    defp append_die(expr, die) do
      sides = String.trim_leading(die, "d")

      case Regex.run(~r/(\d+)d#{sides}$/, expr) do
        [full, count] ->
          String.replace(expr, full, "#{String.to_integer(count) + 1}d#{sides}", global: false)

        _ ->
          expr <> "+1" <> die
      end
    end

    # Flattens the result into a render-friendly list of {value, kept} pills.
    defp breakdown(%Result{groups: groups}) do
      Enum.flat_map(groups, fn
        %{kind: :dice, rolls: rolls} -> Enum.map(rolls, &%{value: &1.value, kept: &1.kept})
        %{kind: :modifier, subtotal: n} -> [%{value: n, kept: true}]
      end)
    end
  end
end
