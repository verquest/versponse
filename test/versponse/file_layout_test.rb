# frozen_string_literal: true

require "test_helper"

# Zeitwerk loads a constant from the file named after it, so a second class at the same level in a file
# exists only once its neighbour has loaded (and raises NameError depending on load order)
class Versponse::FileLayoutTest < Minitest::Test
  LIB = File.expand_path("../../lib/versponse", __dir__)

  def test_each_file_defines_one_class_at_its_level
    offenders = Dir["#{LIB}/**/*.rb"].filter_map do |path|
      classes = File.readlines(path).filter_map { |line| line[/\A(\s*)class (\w+)/] && [$1.size, $2] }
      next if classes.empty?

      level = classes.first.first
      extra = classes.drop(1).select { |indent, _| indent == level }.map(&:last)
      "#{path.delete_prefix("#{LIB}/")}: #{extra.join(", ")}" if extra.any?
    end

    assert_empty offenders
  end
end
