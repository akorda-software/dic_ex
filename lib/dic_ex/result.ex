defmodule DicEx.Result do
  @moduledoc """
  The outcome of a roll: a structured, AI/consumer-friendly record plus helpers
  to reduce it to plain data (`to_map/1`) or flatten its kept dice (`kept_values/1`).

  A result is made of one or more *groups*. Each group is either a dice pool
  (e.g. `2d20kh1`) or a constant modifier (e.g. `5`). Dice groups carry the
  individual die outcomes so you can render them, show advantage/disadvantage,
  or feed them to an LLM as structured data.

  ## Example

      iex> DicEx.roll("2d20kh1 + 5")
      %DicEx.Result{
        expression: "2d20kh1 + 5",
        total: 23,
        groups: [
          %{kind: :dice, notation: nil, sides: 20, subtotal: 18,
            modifiers: [{:keep_high, 1}],
            rolls: [%{value: 18, kept: true, exploded: false},
                    %{value: 7, kept: false, exploded: false}]},
          %{kind: :modifier, notation: nil, sides: nil, subtotal: 5,
            modifiers: [], rolls: []}
        ]
      }

  Note the per-group `notation` is left `nil`; the full expression is on the
  top-level `expression` field.
  """

  defstruct expression: nil, total: 0, groups: []

  @type roll :: %{
          value: pos_integer(),
          kept: boolean(),
          exploded: boolean()
        }

  @type group :: %{
          kind: :dice | :modifier,
          notation: String.t() | nil,
          sides: pos_integer() | nil,
          subtotal: integer(),
          modifiers: [term()],
          rolls: [roll()]
        }

  @type t :: %__MODULE__{
          expression: String.t() | nil,
          total: integer(),
          groups: [group()]
        }

  @doc """
  Builds the payload the JavaScript hook expects for a roll animation:
  `%{expression, total, groups: [%{sides, subtotal, rolls: [%{value, kept, exploded}]}]}`.
  """
  def to_roll_event(%__MODULE__{} = result) do
    %{
      expression: result.expression,
      total: result.total,
      groups:
        Enum.map(result.groups, fn g ->
          %{
            sides: g.sides,
            subtotal: g.subtotal,
            rolls: Enum.map(g.rolls, &Map.take(&1, [:value, :kept, :exploded]))
          }
        end)
    }
  end

  @doc """
  Reduces a result to a plain map, ready for `Phoenix.json`/LLM consumption.
  """
  def to_map(%__MODULE__{} = result) do
    %{
      expression: result.expression,
      total: result.total,
      groups: Enum.map(result.groups, &group_to_map/1)
    }
  end

  defp group_to_map(group) do
    group
    |> Map.take([:kind, :notation, :sides, :subtotal, :modifiers, :rolls])
  end

  @doc """
  Extracts just the flat list of *kept* die values across all dice groups,
  ignoring modifiers and dropped dice. Useful for quick sanity checks.
  """
  def kept_values(%__MODULE__{groups: groups}) do
    Enum.flat_map(groups, fn
      %{kind: :dice, rolls: rolls} -> Enum.filter(rolls, & &1.kept) |> Enum.map(& &1.value)
      _ -> []
    end)
  end
end
