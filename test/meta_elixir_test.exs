defmodule MetaElixirTest do
  use ExUnit.Case
  doctest MetaElixir

  defmacro assurt(expression) do
    quote do
      unless unquote(expression) do
        raise "Assertion failed!"
      end
    end
  end

  test "assurt macro" do
    assurt true
    assert_raise RuntimeError, fn -> assurt false end
  end

  defmacro iff(expression, body) do
    quote do
      case unquote(expression) do
        true -> unquote(body[:do])
        false -> unquote(body[:else])
      end
    end
  end

  test "iff" do
    foo = if true do
      :foo
    end

    bar = if false do
      :nope
    else
      :bar
    end

    assert foo == :foo
    assert bar == :bar
  end

  defmacro do_what_i_meant(expr) do
    expr = put_elem(expr, 0, :length)
    expr
  end

  test "macros" do
    assert do_what_i_meant(langth([1,2,3])) == 3
    assert do_what_i_meant(lolwat([1,2,3])) == 3
  end

  test "langths" do
    expr = quote do
      langth([1,2]) + langth([3,4])
    end

    fix_langth = fn
      {:langth, meta, args} -> {:length, meta, args}
      node -> node
    end

    fixed_expr = Macro.prewalk(expr, fix_langth)
    {result, _} = Code.eval_quoted(fixed_expr)

    assert result == 4
  end

  test "traverse" do
    called_before_node_is_traversed = fn node, acc ->
      IO.puts "before: #{node}"
      {node, acc}
    end
    called_after_node_is_traversed = fn node, acc ->
      IO.puts "after: #{node}"
      {node, acc}
    end

    expr = quote do
      "foo"
    end

    Macro.traverse expr, nil, called_before_node_is_traversed, called_after_node_is_traversed
  end

  test "traversing expressions" do
    expressions = quote do
      "first"
      "second"
    end

    pre = fn expr, acc ->
      str = "before: #{Macro.to_string(expr)}"
      {expr, [str|acc]}
    end
    post = fn expr, acc ->
      str = "after: #{Macro.to_string(expr)}"
      {expr, [str|acc]}
    end

    {_, result} = Macro.traverse(expressions, [], pre, post)

    assert result == [
      ~s{after: (\n  "first"\n  "second"\n)},
      ~s{after: "second"},
      ~s{before: "second"},
      ~s{after: "first"},
      ~s{before: "first"},
      ~s{before: (\n  "first"\n  "second"\n)},
    ]
  end

  test "pre/postwalk with accumulator; count expressions" do
    expressions = quote do
      foo(:bar)
    end

    counter = fn
      expr, counter -> {expr, counter+1}
    end
    {_, precount} = Macro.prewalk(expressions, 0, counter)
    {_, postcount} = Macro.postwalk(expressions, 0, counter)

    assert precount == 2
    assert postcount == 2
  end

  test "pre/postwalk with accumulator; count matches" do
    expressions = quote do
      first = :foo
      second = :bar
      [first, second]
    end

    count_matches = fn
      {:=, _meta, _args} = node, counter -> {node, counter+1}
      node, acc -> {node, acc}
    end

    {_, precount} = Macro.prewalk(expressions, 0, count_matches)
    {_, postcount} = Macro.postwalk(expressions, 0, count_matches)

    assert precount == 2
    assert postcount == 2
  end

  test "pre/postwalk with accumulator; gather literal atoms" do
    expressions = quote do
      lol = :wat
      is_atom(lol)
      is_atom(:lol)
    end

    gather_atoms = fn
      node, atoms when is_atom(node) -> {node, [node|atoms]}
      node, acc -> {node, acc}
    end

    {_, preatoms} = Macro.prewalk(expressions, [], gather_atoms)
    {_, postatoms} = Macro.postwalk(expressions, [], gather_atoms)

    assert preatoms == [:lol, :wat]
    assert postatoms == [:lol, :wat]
  end

  test "pre/postwalk with accumulator; describe expression" do
    expressions = quote do
      is_atom(:lolwat)
    end

    describe_node = fn
      node, descriptions when is_tuple(node) -> {node, ["a function"|descriptions]}
      node, descriptions when is_atom(node) -> {node, ["a literal atom"|descriptions]}
      node, acc -> {node, acc}
    end

    {_, predesc} = Macro.prewalk(expressions, [], describe_node)
    {_, postdesc} = Macro.postwalk(expressions, [], describe_node)

    assert predesc == ["a literal atom", "a function"]
    assert postdesc == ["a function", "a literal atom"]
    # Note: Order is different based on pre/post
  end

  test "pre/postwalk with dissipator (opposite of accumulator); replace expression" do
    quoted_expression = quote do
      String.upcase(___)
    end

    expected_expression = quote do
      String.upcase("ohai")
    end

    replace = fn
      {:___, _, _}, [replacement|rest] -> {replacement, rest}
      node, replacements -> {node, replacements}
    end

    {updated_expression, _} = Macro.prewalk(quoted_expression, ["ohai"], replace)
    {result, _} = Code.eval_quoted(updated_expression)

    assert updated_expression == expected_expression
    assert result == "OHAI"
  end

  test "koans" do
    koan = quote do
      ___ + ___ == 3
    end

    replace_blank = fn
      {:___, _, _}, [answer|rest] -> {answer, rest}
      node, acc -> {node, acc}
    end

    answers = [1, 2]
    {answered_koan, []} = Macro.prewalk(koan, answers, replace_blank)
    {result, _} = Code.eval_quoted(answered_koan)

    assert result == true
  end
end
