# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
require "test_helper"

class Oknola::NoInlineHandlersTest < ActiveSupport::TestCase
  INLINE_HANDLER = /\bon(abort|blur|change|click|error|focus|input|key(down|press|up)|load|mouse\w+|submit)\b\s*[:=]/
  JAVASCRIPT_URL = /javascript:/i

  test "view and component source has no inline handlers or javascript URLs" do
    files = %w[app/views app/components].flat_map do |directory|
      Dir.glob(Rails.root.join(directory, "**/*.{erb,rb}"))
    end

    violations = files.flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, index|
        next unless INLINE_HANDLER.match?(line) || JAVASCRIPT_URL.match?(line)

        "#{Pathname.new(file).relative_path_from(Rails.root)}:#{index + 1}"
      end
    end

    assert_empty violations
  end

  test "inline handler scan catches the issue's former patterns" do
    old_snippets = [
      "onerror: ProviderLogo::REMOVE_ON_ERROR",
      "onclick: \"return confirm(...)\"",
      "href: \"javascript:history.back()\"",
      "onchange: \"this.form.requestSubmit()\"",
      "onclick=\"event.stopPropagation();\"",
      "onclick: \"window.location.reload()\"",
      "window.onload = function() {}"
    ]

    old_snippets.each do |snippet|
      assert INLINE_HANDLER.match?(snippet) || JAVASCRIPT_URL.match?(snippet), "scan missed #{snippet}"
    end
  end
end
