if Code.ensure_loaded?(Phoenix.LiveComponent) and Code.ensure_loaded?(Jason) do
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

      * `default` — initial expression (default `"1d20"`). Only applied when it
        changes, so parent re-renders never wipe what the player typed.
      * `theme` — `"obsidian"` (default), `"arcane"` or `"dnd"`, or a custom
        palette map (see `DicEx.Theme`).
      * `engine` — `"3d"` (default; Three.js + Rapier physics) or `"2d"` (canvas,
        no physics: the die tumbles in 2D and lands on the authoritative value).
      * `physics` — `false` (default) or `true`. By default the server's roll is
        always the result: the 3D dice tumble physically and settle on the
        faces Elixir chose. With `physics={true}` the 3D engine becomes
        *physics-is-truth*: the faces that land are reported back and become
        the result. The client decides that outcome, so only use it where
        cheating does not matter. It only applies to pools of d4/d6/d8/d10/d12/d20
        without explode or reroll; other rolls stay server-authoritative.
      * `rng` — RNG module or `{module, state}` for the rolls (default `nil` ⇒
        `DicEx.RNG.Default`). Pass `DicEx.RNG.Entropy` for cryptographic,
        non-replayable randomness.
      * `limits` — keyword list of parse limits passed to `DicEx.roll_e/2`
        (`:max_dice`, `:max_sides`, `:max_length`).
      * `labels` — map overriding the UI strings: `:add`, `:clear`, `:roll`,
        `:rolling`, `:placeholder`, `:input`. Defaults are English.
      * `reveal_timeout` — milliseconds before the result is revealed even if the
        dice never report settling (default `6000`).
      * `on_roll` — a `pid`, registered name, `{name, node}`, `{:global, name}`
        or `{:via, module, name}` to notify of every roll via `send/2` with
        `{:dic_ex_rolled, %{result: result, component: id}}`.

    ## Receiving rolls

        <.live_component module={DicExWeb.DiceRoller} id="roller"
          on_roll={self()} />

        def handle_info({:dic_ex_rolled, %{result: result}}, socket) do
          # result is a %DicEx.Result{}; feed its JSON map to the LLM
          {:noreply, socket}
        end
    """

    use Phoenix.LiveComponent

    # The component is only defined when Phoenix LiveView is available so the
    # pure-rolling core stays usable without any web dependency.

    require Logger

    alias DicEx.{Parser, Result, Theme}
    alias DicEx.RNG.Deterministic

    @quick_dice ~w(d4 d6 d8 d10 d12 d20)

    # Geometry the 3D engine can read a landed face from without bias.
    @physical_sides [4, 6, 8, 10, 12, 20]

    @default_labels %{
      add: "add",
      clear: "clear",
      roll: "Roll",
      rolling: "rolling…",
      placeholder: "1d4+2d6, 2d20kh1+5, 8d6! ...",
      input: "Dice expression"
    }

    # Fallback only: if the dice never report settling (scene failed to init,
    # tab was backgrounded, ...) reveal anyway after a generous timeout. The
    # "dic_ex:settled"/"dic_ex:landed" events are the primary, in-sync paths.
    @reveal_fallback 6000

    defp quick_dice, do: @quick_dice

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

      name =
        if is_binary(theme) or (is_atom(theme) and not is_nil(theme)),
          do: to_string(theme)

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
              title={"#{@labels.add} #{d}"}
              phx-click="add-die"
              phx-target={@myself}
              phx-value-die={d}
            >
              {d}
            </button>
          </div>

          <form
            phx-submit="roll"
            phx-change="change"
            phx-target={@myself}
            class="dicex-form"
          >
            <input
              class="dicex-input"
              type="text"
              name="expression"
              value={@expression}
              placeholder={@labels.placeholder}
              aria-label={@labels.input}
              maxlength={@max_length}
              autocomplete="off"
            />
            <button type="button" class="dicex-clear-btn" phx-click="clear" phx-target={@myself}>
              {@labels.clear}
            </button>
            <button type="submit" class="dicex-roll-btn">{@labels.roll}</button>
          </form>
        </div>

        <div class="dicex-error" role="alert" :if={@error}>{@error}</div>

        <div class="dicex-result" :if={@rolling}>
          <div class="dicex-total dicex-rolling-total">{@labels.rolling}</div>
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
       |> assign(:default, nil)
       |> assign(:result, nil)
       |> assign(:pending_result, nil)
       |> assign(:pending_authoritative, true)
       |> assign(:rolling, false)
       |> assign(:roll_nonce, 0)
       |> assign(:error, nil)
       |> assign_theme("obsidian")
       |> assign(:engine, "3d")
       |> assign(:physics, false)
       |> assign(:rng, nil)
       |> assign(:limits, [])
       |> assign(:max_length, Parser.default_limits().max_length)
       |> assign(:labels, @default_labels)
       |> assign(:reveal_timeout, @reveal_fallback)
       |> assign(:on_roll, nil)}
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

    # The fallback timer carries the roll's nonce so it can't reveal a later
    # roll's result if it fires stale (e.g. roll A settled, roll B started,
    # then A's timer wakes).
    @impl true
    def update(%{reveal_nonce: nonce}, socket) do
      {:ok,
       if(socket.assigns.roll_nonce == nonce,
         do: maybe_reveal(socket, socket.assigns.pending_result),
         else: socket
       )}
    end

    def update(%{id: id} = opts, socket) do
      limits = Map.get(opts, :limits, [])

      socket =
        socket
        |> assign(:id, id)
        |> assign_theme(Map.get(opts, :theme, "obsidian"))
        |> assign(:engine, if(Map.get(opts, :engine) == "2d", do: "2d", else: "3d"))
        |> assign(:physics, Map.get(opts, :physics, false) == true)
        |> assign(:rng, Map.get(opts, :rng))
        |> assign(:limits, limits)
        |> assign(
          :max_length,
          Keyword.get(limits, :max_length, Parser.default_limits().max_length)
        )
        |> assign(:labels, Map.merge(@default_labels, Map.get(opts, :labels, %{})))
        |> assign(:on_roll, Map.get(opts, :on_roll))
        |> assign(:reveal_timeout, Map.get(opts, :reveal_timeout, @reveal_fallback))

      # `default` seeds the input once (and again only if the host changes it),
      # so a parent re-render can't overwrite what the player has built.
      socket =
        case Map.fetch(opts, :default) do
          {:ok, default} when default != socket.assigns.default ->
            socket |> assign(:default, default) |> assign(:expression, default)

          _ ->
            socket
        end

      {:ok, socket}
    end

    # Tray buttons accumulate dice into the hand, so mixed pools like
    # "1d4+2d6" build up naturally (click d4, d6, d6). Repeated clicks on the
    # same plain trailing term increment its count instead of stacking terms.
    @impl true
    def handle_event("add-die", %{"die" => die}, socket) when die in @quick_dice do
      {:noreply,
       socket
       |> assign(:expression, append_die(socket.assigns.expression, die))
       |> assign(:error, nil)}
    end

    def handle_event("add-die", _params, socket), do: {:noreply, socket}

    # Keeps the server's copy of the expression in sync with what is typed, so
    # tray clicks append to the visible text rather than to a stale value.
    def handle_event("change", %{"expression" => expression}, socket)
        when is_binary(expression) do
      {:noreply, assign(socket, :expression, expression)}
    end

    def handle_event("change", _params, socket), do: {:noreply, socket}

    def handle_event("clear", _params, socket) do
      {:noreply, socket |> assign(:expression, "") |> assign(:error, nil)}
    end

    # Primary reveal path: the JS hook reports that every die has finished its
    # settle animation, so we reveal the result exactly in sync with the dice.
    # The event name carries this component's id so several rollers can coexist
    # in the same LiveView without cross-firing each other's reveal.
    def handle_event("dic_ex:settled:" <> _id, params, socket) do
      if stale?(socket, params),
        do: {:noreply, socket},
        else: {:noreply, maybe_reveal(socket, socket.assigns.pending_result)}
    end

    # The 3D hook reports the faces that are up once the dice rest. For an
    # authoritative roll (the default) those are the faces the server chose and
    # the event is just a "settled" signal. In physics mode the landed values
    # become the result after validation; anything implausible falls back to
    # the server's own roll.
    def handle_event("dic_ex:landed:" <> _id, params, socket) do
      %{pending_result: pending, pending_authoritative: authoritative} = socket.assigns

      cond do
        stale?(socket, params) or is_nil(pending) ->
          {:noreply, socket}

        authoritative ->
          {:noreply, maybe_reveal(socket, pending)}

        true ->
          {:noreply, maybe_reveal(socket, physical_result(pending, params["values"]))}
      end
    end

    def handle_event("roll", %{"expression" => expression}, socket) when is_binary(expression) do
      perform_roll(expression, socket)
    end

    def handle_event("roll", _params, socket) do
      perform_roll(socket.assigns.expression, socket)
    end

    defp perform_roll(expression, socket) do
      socket = assign(socket, :expression, expression)

      case DicEx.roll_e(expression, roll_opts(socket.assigns)) do
        {:ok, result} ->
          # animation kicks off immediately; the result is revealed when the dice
          # report settling/landing, with a fallback timer as safety. The nonce
          # tags this roll so stale events and timers can't reveal it twice or
          # reveal the wrong roll.
          nonce = socket.assigns.roll_nonce + 1

          authoritative =
            not (socket.assigns.physics and socket.assigns.engine == "3d" and
                   physically_rollable?(expression))

          send_update_after(
            self(),
            __MODULE__,
            %{id: socket.assigns.id, reveal_nonce: nonce},
            socket.assigns.reveal_timeout
          )

          {:noreply,
           socket
           |> assign(:rolling, true)
           |> assign(:result, nil)
           |> assign(:error, nil)
           |> assign(:pending_result, result)
           |> assign(:pending_authoritative, authoritative)
           |> assign(:roll_nonce, nonce)
           |> push_roll(result, authoritative, nonce)}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:error, reason)
           |> push_event(error_event(socket.assigns.id), %{message: reason})}
      end
    end

    defp roll_opts(%{rng: rng, limits: limits}) do
      if rng, do: [{:rng, rng} | limits], else: limits
    end

    # Events from an older roll (in flight when a new one started) carry its
    # nonce and are dropped. Hooks that predate the nonce send none.
    defp stale?(socket, params) do
      case params do
        %{"nonce" => nonce} -> nonce != socket.assigns.roll_nonce
        _ -> false
      end
    end

    # Physics-is-truth only works when every die maps 1:1 onto a thrown die
    # with readable, unbiased geometry: no explode/reroll (those need extra or
    # hidden rolls) and only the standard polyhedra.
    defp physically_rollable?(expression) do
      case Parser.parse(expression) do
        {:ok, ast} -> physical_node?(ast)
        _ -> false
      end
    end

    defp physical_node?({:num, _}), do: true
    defp physical_node?({:neg, node}), do: physical_node?(node)
    defp physical_node?({:op, _, l, r}), do: physical_node?(l) and physical_node?(r)

    defp physical_node?({:dice, _count, sides, mods}) do
      sides in @physical_sides and
        not Enum.any?(mods, &(match?({:explode, _}, &1) or match?({:reroll, _, _, _}, &1)))
    end

    # Re-evaluates the expression with the landed faces as the dice values, so
    # keep/drop still apply and the total matches the table. The values come
    # from the client, so they must line up exactly with the thrown dice.
    defp physical_result(%Result{} = pending, values) do
      sides = for %{kind: :dice, sides: s, rolls: rolls} <- pending.groups, _ <- rolls, do: s

      valid? =
        is_list(values) and length(values) == length(sides) and
          Enum.all?(Enum.zip(values, sides), fn {v, s} -> is_integer(v) and v in 1..s end)

      if valid? do
        DicEx.roll(pending.expression, rng: {Deterministic, values})
      else
        Logger.warning("[dicEx] ignoring invalid landed values: #{inspect(values, limit: 20)}")
        pending
      end
    end

    # Per-instance event names. `push_event/3` broadcasts to every hook on the
    # LiveView, so we suffix the roll/error channels with the component id and
    # each hook only listens for its own.
    defp roll_event(id), do: "dic_ex:roll:#{id}"
    defp error_event(id), do: "dic_ex:error:#{id}"

    defp push_roll(socket, %Result{} = result, authoritative, nonce) do
      payload =
        result
        |> Result.to_roll_event()
        |> Map.merge(%{authoritative: authoritative, nonce: nonce})

      push_event(socket, roll_event(socket.assigns.id), payload)
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
      case socket.assigns.on_roll do
        nil -> :ok
        dest -> deliver(dest, {@rolled_msg, %{result: result, component: socket.assigns.id}})
      end
    end

    # A missing or malformed `on_roll` target must never crash the host
    # LiveView mid-reveal; log it instead.
    defp deliver(dest, payload) do
      case GenServer.whereis(dest) do
        nil -> Logger.warning("[dicEx] on_roll target #{inspect(dest)} is not alive")
        target -> send(target, payload)
      end
    rescue
      e in [ArgumentError, FunctionClauseError] ->
        Logger.warning("[dicEx] invalid on_roll target #{inspect(dest)}: #{Exception.message(e)}")
    end

    defp append_die("", die), do: "1" <> die

    defp append_die(expr, "d" <> sides = die) do
      trailing = ~r/(?<![\dA-Za-z])(\d+)d#{sides}$/

      case Regex.run(trailing, expr) do
        [_full, count] ->
          Regex.replace(trailing, expr, "#{String.to_integer(count) + 1}d#{sides}")

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
