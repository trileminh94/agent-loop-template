defmodule AgentLoop.Tools.ReadFilesTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Tools.Context
  alias AgentLoop.Tools.ReadFiles
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

  test "reads multiple files in parallel", %{tmp: tmp} do
    a = Path.join(tmp, "a.txt")
    b = Path.join(tmp, "b.txt")
    File.write!(a, "alpha")
    File.write!(b, "beta")

    assert {:ok, json} = ReadFiles.execute(%{"paths" => [a, b]}, %Context{})

    assert %{
             ^a => "alpha",
             ^b => "beta"
           } = Jason.decode!(json)
  end

  test "returns error entries for missing files", %{tmp: tmp} do
    missing = Path.join(tmp, "missing.txt")

    assert {:ok, json} = ReadFiles.execute(%{"paths" => [missing]}, %Context{})
    assert %{^missing => "Error: could not stat" <> _} = Jason.decode!(json)
  end

  test "skips oversized files", %{tmp: tmp} do
    big = Path.join(tmp, "big.bin")
    File.write!(big, String.duplicate("x", 60_000))

    assert {:ok, json} = ReadFiles.execute(%{"paths" => [big]}, %Context{})
    result = Jason.decode!(json)
    assert result[big] =~ "is 60000 bytes (max 50000)"
  end

  test "limits paths to max", %{tmp: tmp} do
    paths = for i <- 1..15, do: Path.join(tmp, "#{i}.txt")
    for p <- paths, do: File.write!(p, "x")

    assert {:ok, json} = ReadFiles.execute(%{"paths" => paths}, %Context{})
    map = Jason.decode!(json)
    assert map_size(map) == 10
  end
end
