defmodule AgentLoop.Tools.ExploreTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Tools.Context
  alias AgentLoop.Tools.Explore
  alias AgentLoop.Tools.Workspace

  setup do
    tmp = Path.join(System.tmp_dir!(), "agent_loop_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    Workspace.configure(root: tmp, restrict: false)

    on_exit(fn ->
      Workspace.reset()
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "returns directory listing and flat file list", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, "sub"))
    File.write!(Path.join(tmp, "a.txt"), "a")
    File.write!(Path.join(tmp, "sub/b.txt"), "b")

    assert {:ok, output} = Explore.execute(%{"path" => tmp}, %Context{})
    assert output =~ "a.txt"
    assert output =~ "sub"
    assert output =~ "sub/b.txt"
  end

  test "caps file list at 30 files", %{tmp: tmp} do
    for i <- 1..40, do: File.write!(Path.join(tmp, "#{i}.txt"), "x")

    assert {:ok, output} = Explore.execute(%{"path" => tmp}, %Context{})

    file_section = output |> String.split("--- files") |> List.last()

    file_lines =
      file_section
      |> String.split("\n")
      |> Enum.filter(&String.ends_with?(&1, ".txt"))

    assert length(file_lines) == 30
  end
end
