# frozen_string_literal: true

require "test_helper"

class TestScriptingCommands < Minitest::Test
  include Helper::Client

  def setup
    super
    r.script_flush # Ensure the script cache is empty before running tests
  end

  def to_sha(script)
    r.script(:load, script)
  end

  def test_script_exists
    a = to_sha("return 1")
    b = a.succ

    r.invoke_script(a)

    assert_equal true, r.script(:exists, a)

    assert_equal false, r.script(:exists, b)
    assert_equal [true], r.script(:exists, [a])
    assert_equal [false], r.script(:exists, [b])
    assert_equal [true, false], r.script(:exists, [a, b])
  end

  def test_script_flush
    sha = to_sha("return 1")
    r.invoke_script(sha)
    assert r.script(:exists, sha)
    assert_equal "OK", r.script(:flush)
    assert !r.script(:exists, sha)
  end

  def test_script_kill
    # there is no script running
    assert_raises(Valkey::CommandError) { r.script_kill }
  end
end
