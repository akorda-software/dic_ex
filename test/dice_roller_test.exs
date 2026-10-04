defmodule DicExWeb.DiceRollerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias DicEx.RNG.Deterministic
  alias DicExWeb.DiceRoller
  alias Phoenix.LiveView.{Socket, Utils}

  defp socket(opts \\ %{}) do
    {:ok, socket} = DiceRoller.mount(%Socket{private: %{live_temp: %{}}})
    {:ok, socket} = DiceRoller.update(Map.merge(%{id: "roller"}, opts), socket)
    socket
  end

  defp event(socket, name, params) do
    {:noreply, socket} = DiceRoller.handle_event(name, params, socket)
    socket
  end

  defp roll(socket, expression), do: event(socket, "roll", %{"expression" => expression})

  defp pushed(socket), do: Utils.get_push_events(socket)

  describe "rolling" do
    test "remembers the submitted expression" do
      socket = socket() |> roll("2d6")
      assert socket.assigns.expression == "2d6"
      assert socket.assigns.pending_result.expression == "2d6"
    end

    test "pushes an authoritative roll tagged with its nonce by default" do
      socket = socket() |> roll("1d20")
      assert [["dic_ex:roll:roller", payload]] = pushed(socket)
      assert payload.authoritative == true
      assert payload.nonce == socket.assigns.roll_nonce
    end

    test "invalid expressions surface an error instead of rolling" do
      socket = socket() |> roll("1d6r<=6")
      assert socket.assigns.error =~ "every face"
      refute socket.assigns.rolling
      assert render_component(DiceRoller, id: "r") =~ "dicex-stage"
    end

    test "the reveal fallback is delivered to the LiveView process" do
      socket = socket(%{reveal_timeout: 10}) |> roll("1d20")
      nonce = socket.assigns.roll_nonce
      # send_update_after targets self(): the old Task-based timer sent it to
      # the Task's own pid, so the fallback never fired.
      assert_receive {:phoenix, :send_update, {{DiceRoller, "roller"}, %{reveal_nonce: ^nonce}}},
                     500
    end

    @tag :capture_log
    test "fallback reveals only the roll it was armed for" do
      socket = socket() |> roll("1d20")
      {:ok, stale} = DiceRoller.update(%{reveal_nonce: 0}, socket)
      assert stale.assigns.rolling
      {:ok, fresh} = DiceRoller.update(%{reveal_nonce: socket.assigns.roll_nonce}, socket)
      refute fresh.assigns.rolling
      assert fresh.assigns.result == socket.assigns.pending_result
    end
  end

  describe "landed events" do
    test "clearing the input mid-roll does not crash the reveal" do
      socket = socket() |> roll("1d20") |> event("clear", %{})
      socket = event(socket, "dic_ex:landed:roller", %{"values" => [20]})
      refute socket.assigns.rolling
      assert socket.assigns.result.expression == "1d20"
    end

    test "authoritative rolls ignore the values the client reports" do
      socket = socket(%{rng: {Deterministic, [7]}}) |> roll("1d20")
      socket = event(socket, "dic_ex:landed:roller", %{"values" => [20]})
      assert socket.assigns.result.total == 7
    end

    test "physics mode uses validated landed values" do
      socket = socket(%{physics: true, rng: {Deterministic, [7, 3]}}) |> roll("2d20kh1")
      assert [[_, %{authoritative: false}]] = pushed(socket)
      socket = event(socket, "dic_ex:landed:roller", %{"values" => [12, 19]})
      assert socket.assigns.result.total == 19
    end

    test "physics mode rejects malformed or out-of-range values" do
      for values <- [["20"], [nil], [21], [0], [5, 5], "20", nil] do
        socket = socket(%{physics: true, rng: {Deterministic, [7]}}) |> roll("1d20")

        log =
          capture_log(fn ->
            socket = event(socket, "dic_ex:landed:roller", %{"values" => values})
            assert socket.assigns.result.total == 7
          end)

        assert log =~ "invalid landed values"
      end
    end

    test "physics mode stays authoritative for explode, reroll and odd dice" do
      for expression <- ["1d6!", "1d20r1", "1d100", "1d7", "2d6+1d3"] do
        socket = socket(%{physics: true}) |> roll(expression)
        assert [[_, %{authoritative: true}]] = pushed(socket), expression
      end
    end

    test "the 2D engine is always authoritative" do
      socket = socket(%{physics: true, engine: "2d"}) |> roll("1d20")
      assert [[_, %{authoritative: true}]] = pushed(socket)
    end

    test "events from a previous roll are ignored" do
      socket = socket() |> roll("1d20")
      stale = socket.assigns.roll_nonce - 1
      socket = event(socket, "dic_ex:settled:roller", %{"nonce" => stale})
      assert socket.assigns.rolling
      socket = event(socket, "dic_ex:settled:roller", %{"nonce" => socket.assigns.roll_nonce})
      refute socket.assigns.rolling
    end
  end

  describe "state" do
    test "parent re-renders don't reset the expression to the default" do
      socket = socket(%{default: "2d6"}) |> event("add-die", %{"die" => "d6"})
      assert socket.assigns.expression == "3d6"
      {:ok, socket} = DiceRoller.update(%{id: "roller", default: "2d6", theme: "arcane"}, socket)
      assert socket.assigns.expression == "3d6"
      {:ok, socket} = DiceRoller.update(%{id: "roller", default: "1d8"}, socket)
      assert socket.assigns.expression == "1d8"
    end

    test "typing keeps the expression in sync for tray clicks" do
      socket = socket() |> event("change", %{"expression" => "1d8+2"})
      socket = event(socket, "add-die", %{"die" => "d4"})
      assert socket.assigns.expression == "1d8+2+1d4"
    end

    test "tray increments the trailing term, not the first match" do
      socket = socket(%{default: "1d6+1d8+1d6"}) |> event("add-die", %{"die" => "d6"})
      assert socket.assigns.expression == "1d6+1d8+2d6"
      socket = socket(%{default: "1d16"}) |> event("add-die", %{"die" => "d6"})
      assert socket.assigns.expression == "1d16+1d6"
    end

    test "unknown tray values are ignored" do
      socket = socket() |> event("add-die", %{"die" => "d6)|("})
      assert socket.assigns.expression == "1d20"
    end
  end

  describe "on_roll" do
    defp reveal(opts) do
      socket = socket(opts) |> roll("1d20")
      event(socket, "dic_ex:settled:roller", %{})
    end

    test "notifies a pid" do
      reveal(%{on_roll: self()})
      assert_received {:dic_ex_rolled, %{component: "roller", result: %DicEx.Result{}}}
    end

    test "notifies a registered name" do
      Process.register(self(), :dic_ex_on_roll_test)
      reveal(%{on_roll: :dic_ex_on_roll_test})
      assert_received {:dic_ex_rolled, _}
    end

    test "a dead or malformed target logs instead of crashing" do
      for target <- [:dic_ex_not_registered, {:via, Registry, {DicEx.NoSuchRegistry, :x}}, "x"] do
        log = capture_log(fn -> refute reveal(%{on_roll: target}).assigns.rolling end)
        assert log =~ "on_roll"
      end
    end
  end

  describe "render" do
    test "uses English labels by default and accepts overrides" do
      html = render_component(DiceRoller, id: "r")
      assert html =~ "Roll"
      assert html =~ "clear"

      html = render_component(DiceRoller, id: "r", labels: %{roll: "Tirar", clear: "limpiar"})
      assert html =~ "Tirar"
      assert html =~ "limpiar"
    end
  end
end
