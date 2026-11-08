# Modified by Cardona Labs, LLC, 2026-11-08, AGPL-3.0
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

  test "English translations use Finance outside the About credit" do
    offenses = []

    translation_leaves(I18n.backend.translations(do_init: true).fetch(:en)) do |path, value|
      next if path.first(2).map(&:to_s) == %w[settings abouts]
      next unless value.match?(/\bSure\b/)

      offenses << path.join(".")
    end

    assert_empty offenses, "Unexpected product names:\n#{offenses.join("\n")}"
    assert_equal "Try Finance for 45 days", I18n.t("onboardings.trial.title", locale: :en)
    assert_equal "Finance, built on Sure (AGPL-3.0).", I18n.t("settings.abouts.show.built_on", locale: :en)
  end

  private
    def translation_leaves(value, path = [], &block)
      case value
      when Hash
        value.each { |key, child| translation_leaves(child, path + [ key ], &block) }
      when Array
        value.each_with_index { |child, index| translation_leaves(child, path + [ index ], &block) }
      when String
        yield path, value
      end
    end

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
