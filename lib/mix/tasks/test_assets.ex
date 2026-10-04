defmodule Mix.Tasks.DicEx.TestAssets do
  @moduledoc "Verifica geometría y ciclo de vida de los hooks con Node, sin instalar paquetes."
  use Mix.Task
  @shortdoc "Tests de los renderizadores de dados"

  @impl true
  def run(_args) do
    {_output, status} =
      System.cmd("node", ["--test", "assets/test/lifecycle.test.mjs"],
        stderr_to_stdout: true,
        into: IO.binstream(:stdio, :line)
      )

    if status != 0, do: Mix.raise("Fallaron los tests de assets de dic_ex")
  end
end
