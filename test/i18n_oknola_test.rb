# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"
require "yaml"

class I18nOknolaTest < ActiveSupport::TestCase
  test "English translations only name Maybe in the About disclaimer" do
    offenses = []

    Rails.root.glob("config/locales/**/en.yml").sort.each do |file|
      locale_leaves(Psych.parse_file(file).root).each do |key, value, line|
        next if key == "en.settings.abouts.show.disclaimer"
        next unless value.match?(/\bMaybe\b/)

        offenses << "#{file}:#{line} (#{key})"
      end
    end

    assert_empty offenses, "Unexpected branding:\n#{offenses.join("\n")}"
  end

  test "view and component templates do not name Maybe" do
    offenses = []

    Rails.root.glob("app/{views,components}/**/*.erb").sort.each do |file|
      file.each_line.with_index(1) do |line, number|
        offenses << "#{file}:#{number}" if line.match?(/\bMaybe\b/)
      end
    end

    assert_empty offenses, "Unexpected branding:\n#{offenses.join("\n")}"
  end

  private
    def locale_leaves(node, path = [])
      case node
      when Psych::Nodes::Mapping
        node.children.each_slice(2).flat_map do |key, value|
          locale_leaves(value, path + [ key.value ])
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index.flat_map do |value, index|
          locale_leaves(value, path + [ index ])
        end
      when Psych::Nodes::Scalar
        [ [ path.join("."), node.value, node.start_line + 1 ] ]
      else
        []
      end
    end
end
