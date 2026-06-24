defmodule DicEx.Theme do
  @moduledoc """
  Theme adapter for the dice roller.

  A theme is a single map of colour keys that drives **both** layers of the UI:

    * the component chrome — emitted as CSS custom properties (`--dicex-*`);
    * the procedurally-drawn die faces — emitted as a canvas palette (JSON) the
      JS hooks consume for the 2D tiles and the 3D textures.

  Pass a built-in name (`:obsidian` / `:arcane` / `:dnd`) or a custom map with any subset
  of the keys (missing ones fall back to the obsidian defaults), so an app can
  skin the roller without forking the package's JS or CSS.

      # built-in
      <.live_component module={DicExWeb.DiceRoller} id="r" theme="arcane" />

      # fully custom
      <.live_component module={DicExWeb.DiceRoller} id="r"
        theme={%{bg: "#0b1220", panel: "#111b2e", edge: "#1f3a5f",
                 ink: "#e6f0ff", accent: "#38bdf8", face: "#0f1c30"}} />

  ## Keys

  Chrome (CSS): `bg`, `panel`, `edge`, `ink`, `muted`, `accent`, `good`, `bad`,
  `stage_glow`, `stage_tile_a`, `stage_tile_b`, `control_bg`, `input_bg`,
  `pill_bg`, `roll_ink`, `roll_border`, `roll_hover`.
  Dice faces (canvas): `face`, `face_edge`, `pip`, `pip_shadow`, `sheen`.
  """

  @defaults %{
    # chrome
    bg: "#14101f",
    panel: "#1c1530",
    edge: "#3b2a63",
    ink: "#e9d8a6",
    muted: "#9a8fc4",
    accent: "#b08a3e",
    good: "#6ee7b7",
    bad: "#f87171",
    stage_glow: "rgba(124, 92, 255, 0.12)",
    stage_tile_a: "#1a1428",
    stage_tile_b: "#16111f",
    control_bg: "#241a38",
    input_bg: "#120e1d",
    pill_bg: "#241a38",
    roll_ink: "#1a1326",
    roll_border: "#5a4520",
    roll_hover: "#c79e54",
    # dice faces
    face: "#1a1326",
    face_edge: "#2d1f44",
    pip: "#e9d8a6",
    pip_shadow: "#7a5fae",
    sheen: "#241a38"
  }

  @builtins %{
    "obsidian" => @defaults,
    "arcane" => %{
      bg: "#f4e4c1",
      panel: "#efe0bc",
      edge: "#b08a3e",
      ink: "#2a1f44",
      muted: "#7a5fae",
      accent: "#6a4f2a",
      good: "#2f9e6e",
      bad: "#b8324b",
      stage_glow: "rgba(176, 138, 62, 0.20)",
      stage_tile_a: "#f1dfb7",
      stage_tile_b: "#ead5a6",
      control_bg: "#f5e7c4",
      input_bg: "#fff8e8",
      pill_bg: "#ead5a6",
      roll_ink: "#1c132b",
      roll_border: "#8d6a2f",
      roll_hover: "#c79e54",
      face: "#f4e4c1",
      face_edge: "#d9c089",
      pip: "#3b2a63",
      pip_shadow: "#9a7bd4",
      sheen: "#fff3d6"
    },
    # Classic D&D table look: dark leather, brass trim, crimson accent and
    # parchment dice with dark pips.
    "dnd" => %{
      bg: "#160b08",
      panel: "#24130d",
      edge: "#9f7635",
      ink: "#f5e7c8",
      muted: "#c59f62",
      accent: "#c7382b",
      good: "#56a35d",
      bad: "#e0493e",
      stage_glow: "rgba(199, 56, 43, 0.22)",
      stage_tile_a: "#24110d",
      stage_tile_b: "#1a0c09",
      control_bg: "#34170f",
      input_bg: "#0f0806",
      pill_bg: "#34170f",
      roll_ink: "#fff3dc",
      roll_border: "#7a231a",
      roll_hover: "#e04a3a",
      face: "#f3e2b3",
      face_edge: "#8f5b2a",
      pip: "#2b160e",
      pip_shadow: "#b98035",
      sheen: "#fff1c9"
    }
  }

  @doc """
  Resolves a theme option into a complete palette map.

  Accepts an atom or string name of a built-in, or a custom map (merged over the
  obsidian defaults). Always returns a full map.
  """
  def resolve(theme)

  def resolve(theme) when is_atom(theme), do: resolve(Atom.to_string(theme))

  def resolve(theme) when is_binary(theme),
    do: Map.merge(@defaults, Map.get(@builtins, theme, %{}))

  def resolve(theme) when is_map(theme), do: Map.merge(@defaults, theme)

  @doc """
  The CSS custom properties for the component chrome, as a keyword list of
  `"--dicex-*" => value` pairs. The component injects these inline.
  """
  def css_vars(palette) do
    [
      {"--dicex-bg", palette.bg},
      {"--dicex-panel", palette.panel},
      {"--dicex-edge", palette.edge},
      {"--dicex-ink", palette.ink},
      {"--dicex-muted", palette.muted},
      {"--dicex-accent", palette.accent},
      {"--dicex-good", palette.good},
      {"--dicex-bad", palette.bad},
      {"--dicex-stage-glow", palette.stage_glow},
      {"--dicex-stage-tile-a", palette.stage_tile_a},
      {"--dicex-stage-tile-b", palette.stage_tile_b},
      {"--dicex-control-bg", palette.control_bg},
      {"--dicex-input-bg", palette.input_bg},
      {"--dicex-pill-bg", palette.pill_bg},
      {"--dicex-roll-ink", palette.roll_ink},
      {"--dicex-roll-border", palette.roll_border},
      {"--dicex-roll-hover", palette.roll_hover}
    ]
  end

  @doc """
  The canvas palette (string keys) the JS hooks expect for drawing die faces.
  Serialize with `Jason.encode!/1` and pass via the `data-palette` attribute.
  """
  def canvas_palette(palette) do
    %{
      "face" => palette.face,
      "faceEdge" => palette.face_edge,
      "pip" => palette.pip,
      "pipShadow" => palette.pip_shadow,
      "border" => palette.edge,
      "sheen" => palette.sheen
    }
  end

  @doc "The built-in theme names as strings."
  def builtins, do: Map.keys(@builtins)

  @doc "The default (obsidian) palette."
  def defaults, do: @defaults
end
