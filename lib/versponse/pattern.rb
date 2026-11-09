# frozen_string_literal: true

module Versponse
  # Writes a Regexp pattern: as an ECMA-262 String, the dialect JSON Schema patterns use
  #
  # @api private
  module Pattern
    # Regexp options ECMA-262 patterns have no inline form for
    OPTIONS = Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE

    # An escape, a bracket expression (kept whole: \A inside one is a literal A), or an inline option group
    TOKEN = /\\.|\[(?:\\.|[^\\\]])*\]|\(\?-?[imx]+(?:-[imx]*)?[:)]/m

    # @param pattern [Regexp, String] pattern as declared
    # @return [String] the String as given, or the Regexp's source with \A and \z written as ^ and $
    # @raise [Versponse::DefinitionError] for a Regexp with options (flags or inline groups), or one using \Z
    def self.source(pattern)
      return pattern unless pattern.is_a?(Regexp)
      raise options_error(pattern) unless (pattern.options & OPTIONS).zero?

      # Tokens are matched from the left, so an escaped backslash before an A stays a literal
      pattern.source.gsub(TOKEN) do |token|
        case token
        when "\\A" then "^"
        when "\\z" then "$"
        when "\\Z" then raise DefinitionError, "pattern: #{pattern.inspect} uses \\Z, which ECMA-262 has no equivalent for; use \\z"
        when /\A\(\?/ then raise options_error(pattern)
        else token
        end
      end
    end

    def self.options_error(pattern)
      DefinitionError.new("pattern: #{pattern.inspect} has options, which ECMA-262 patterns can't carry; use a String pattern")
    end
    private_class_method :options_error
  end
end
