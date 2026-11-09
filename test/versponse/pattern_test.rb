# frozen_string_literal: true

require "test_helper"

class Versponse::PatternTest < Minitest::Test
  def test_strings_are_kept
    assert_equal "^site_", Versponse::Pattern.source("^site_")
  end

  def test_ruby_string_anchors_become_ecma_anchors
    assert_equal "^[a-z]+$", Versponse::Pattern.source(/\A[a-z]+\z/)
    assert_equal "^site_", Versponse::Pattern.source(/^site_/)
  end

  # Escapes are read in pairs, so an escaped backslash before an A is a literal backslash and an A
  def test_escaped_backslashes_are_kept
    assert_equal "\\\\A", Versponse::Pattern.source(/\\A/)
    assert_equal "\\\\^", Versponse::Pattern.source(/\\\A/)
  end

  # Inside a bracket expression \A is a literal A, and \Z a literal Z (Ruby warns about both, so they're built quietly)
  def test_bracket_expressions_are_kept
    assert_equal "[\\A]$", Versponse::Pattern.source(quiet_regexp("[\\A]\\z"))
    assert_equal "[\\Z]x", Versponse::Pattern.source(quiet_regexp("[\\Z]x"))
    assert_equal "^[^\\]]+$", Versponse::Pattern.source(/\A[^\]]+\z/)
  end

  def test_options_raise
    error = assert_raises(Versponse::DefinitionError) { Versponse::Pattern.source(/abc/i) }

    assert_equal "pattern: /abc/i has options, which ECMA-262 patterns can't carry; use a String pattern", error.message
  end

  def test_inline_options_raise
    error = assert_raises(Versponse::DefinitionError) { Versponse::Pattern.source(/(?i)abc/) }

    assert_equal "pattern: /(?i)abc/ has options, which ECMA-262 patterns can't carry; use a String pattern", error.message
    assert_equal "(?:ab)\\(?i", Versponse::Pattern.source(/(?:ab)\(?i/)
  end

  def test_end_before_a_final_newline_raises
    error = assert_raises(Versponse::DefinitionError) { Versponse::Pattern.source(/abc\Z/) }

    assert_equal "pattern: /abc\\Z/ uses \\Z, which ECMA-262 has no equivalent for; use \\z", error.message
  end

  def quiet_regexp(source)
    verbose = $VERBOSE
    $VERBOSE = nil
    Regexp.new(source)
  ensure
    $VERBOSE = verbose
  end
end
