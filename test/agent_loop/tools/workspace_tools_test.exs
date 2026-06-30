defmodule AgentLoop.Tools.WorkspaceToolsTest do
  use ExUnit.Case, async: false

  alias AgentLoop.Tools.EditFile
  alias AgentLoop.Tools.Grep
  alias AgentLoop.Tools.ListFiles
  alias AgentLoop.Tools.Memory
  alias AgentLoop.Tools.ReadFile
  alias AgentLoop.Tools.ShellExec
  alias AgentLoop.Tools.WriteFile
  alias AgentLoop.Tools.Context
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

  describe "ReadFile" do
    test "reads a file", %{tmp: tmp} do
      path = Path.join(tmp, "hello.txt")
      File.write!(path, "line 1\nline 2\nline 3\n")

      assert {:ok, "line 1\nline 2\nline 3\n"} = ReadFile.execute(%{"path" => path}, %Context{})
    end

    test "supports offset and limit", %{tmp: tmp} do
      path = Path.join(tmp, "hello.txt")
      File.write!(path, "a\nb\nc\nd\n")

      assert {:ok, "b\nc"} =
               ReadFile.execute(%{"path" => path, "offset" => 2, "limit" => 2}, %Context{})
    end
  end

  describe "ListFiles" do
    test "lists directory entries", %{tmp: tmp} do
      File.write!(Path.join(tmp, "a.txt"), "a")
      File.mkdir_p!(Path.join(tmp, "sub"))

      assert {:ok, listing} = ListFiles.execute(%{"path" => tmp}, %Context{})
      assert listing =~ "[FILE] a.txt"
      assert listing =~ "[DIR] sub/"
    end

    test "recursive listing includes nested files", %{tmp: tmp} do
      File.mkdir_p!(Path.join(tmp, "sub"))
      File.write!(Path.join(tmp, "sub/nested.txt"), "x")

      assert {:ok, listing} = ListFiles.execute(%{"path" => tmp, "recursive" => true}, %Context{})
      assert listing =~ "[FILE] sub/nested.txt"
    end

    test "details include size and binary marker", %{tmp: tmp} do
      File.write!(Path.join(tmp, "text.txt"), "hello")
      File.write!(Path.join(tmp, "big.bin"), String.duplicate("x", 60_000))

      assert {:ok, listing} = ListFiles.execute(%{"path" => tmp, "details" => true}, %Context{})
      assert listing =~ "[FILE] text.txt 5b [text]"
      assert listing =~ "[FILE] big.bin 60000b [large]"
    end
  end

  describe "WriteFile" do
    test "writes a file", %{tmp: tmp} do
      path = Path.join(tmp, "new.txt")

      assert {:ok, msg} = WriteFile.execute(%{"path" => path, "content" => "hello"}, %Context{})
      assert msg =~ "new.txt"
      assert File.read!(path) == "hello"
    end

    test "creates parent directories", %{tmp: tmp} do
      path = Path.join(tmp, "nested/dir/file.txt")

      assert {:ok, _} = WriteFile.execute(%{"path" => path, "content" => "x"}, %Context{})
      assert File.exists?(path)
    end

    test "appends to a file", %{tmp: tmp} do
      path = Path.join(tmp, "append.txt")
      File.write!(path, "first ")

      assert {:ok, _} =
               WriteFile.execute(
                 %{"path" => path, "content" => "second", "append" => true},
                 %Context{}
               )

      assert File.read!(path) == "first second"
    end
  end

  describe "EditFile" do
    test "replaces exact text", %{tmp: tmp} do
      path = Path.join(tmp, "edit.txt")
      File.write!(path, "hello world")

      assert {:ok, _} =
               EditFile.execute(
                 %{
                   "path" => path,
                   "old_string" => "world",
                   "new_string" => "elixir"
                 },
                 %Context{}
               )

      assert File.read!(path) == "hello elixir"
    end

    test "fails when old_string is not unique", %{tmp: tmp} do
      path = Path.join(tmp, "edit.txt")
      File.write!(path, "x x x")

      assert {:error, "old_string appears 3 times" <> _} =
               EditFile.execute(
                 %{"path" => path, "old_string" => "x", "new_string" => "y"},
                 %Context{}
               )
    end

    test "replace_all changes every occurrence", %{tmp: tmp} do
      path = Path.join(tmp, "edit.txt")
      File.write!(path, "x x x")

      assert {:ok, _} =
               EditFile.execute(
                 %{
                   "path" => path,
                   "old_string" => "x",
                   "new_string" => "y",
                   "replace_all" => true
                 },
                 %Context{}
               )

      assert File.read!(path) == "y y y"
    end
  end

  describe "Grep" do
    test "finds matching lines", %{tmp: tmp} do
      File.write!(Path.join(tmp, "a.ex"), "def foo, do: 1\n")
      File.write!(Path.join(tmp, "b.ex"), "def bar, do: 2\n")

      assert {:ok, matches} = Grep.execute(%{"pattern" => "def foo", "path" => tmp}, %Context{})
      assert matches =~ "a.ex:1:def foo, do: 1"
      refute matches =~ "b.ex"
    end
  end

  describe "ShellExec" do
    test "runs a command and returns output", %{tmp: tmp} do
      assert {:ok, output} = ShellExec.execute(%{"command" => "pwd"}, %Context{})
      assert output =~ Path.basename(tmp)
    end

    test "rejects denied commands" do
      assert {:error, "command 'rm -rf /' is not allowed"} =
               ShellExec.execute(%{"command" => "rm -rf /"}, %Context{})
    end

    test "splits command string into executable and args when args is empty", %{tmp: tmp} do
      File.write!(Path.join(tmp, "a.txt"), "hello")
      assert {:ok, output} = ShellExec.execute(%{"command" => "ls -la"}, %Context{})
      assert output =~ "a.txt"
    end

    test "uses explicit args when provided", %{tmp: tmp} do
      File.write!(Path.join(tmp, "b.txt"), "hello")

      assert {:ok, output} =
               ShellExec.execute(%{"command" => "ls", "args" => ["-la"]}, %Context{})

      assert output =~ "b.txt"
    end
  end

  describe "Memory" do
    test "remembers and recalls notes", %{tmp: tmp} do
      db = Path.join(tmp, "memory.db")
      {:ok, persistence} = AgentLoop.Persistence.new(AgentLoop.Persistence.SQLite, database: db)
      context = %Context{session_id: "test-session", persistence: persistence}

      assert {:ok, _} = Memory.execute(%{"action" => "remember", "note" => "use Elixir"}, context)
      assert {:ok, content} = Memory.execute(%{"action" => "recall"}, context)
      assert content =~ "use Elixir"
    end
  end

  describe "Workspace restriction" do
    test "blocks paths outside workspace when restrict is true", %{tmp: tmp} do
      Workspace.configure(root: tmp, restrict: true)

      assert {:error, "path '/etc/passwd' resolves outside workspace" <> _} =
               ReadFile.execute(%{"path" => "/etc/passwd"}, %Context{})
    end
  end
end
