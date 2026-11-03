# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"
require "open3"

class DesignTokensTest < ActiveSupport::TestCase
  DARK_TOKEN_PATHS = %w[
    budget.unallocated-fill budget.unused-fill
    color.container color.container-hover color.container-inset color.container-inset-hover
    color.destructive color.destructive-subtle color.focus-ring color.info color.link
    color.nav-indicator color.shadow color.success color.surface color.surface-hover
    color.surface-inset color.surface-inset-hover color.tertiary color.toggle-track color.warning
    shadow.lg shadow.md shadow.sm shadow.xl shadow.xs
    utility.bg-inverse utility.bg-inverse-hover utility.bg-overlay utility.bg-subdued
    utility.border-destructive utility.border-inverse utility.border-primary utility.border-secondary
    utility.border-solid utility.border-subdued
    utility.button-bg-accent utility.button-bg-accent-hover
    utility.button-bg-destructive utility.button-bg-destructive-hover utility.button-bg-disabled
    utility.button-bg-ghost-hover utility.button-bg-outline-hover
    utility.button-bg-primary utility.button-bg-primary-hover
    utility.button-bg-secondary utility.button-bg-secondary-hover
    utility.button-bg-secondary-strong utility.button-bg-secondary-strong-hover
    utility.divide-subdued utility.shadow-border-lg utility.shadow-border-md
    utility.shadow-border-sm utility.shadow-border-xl utility.shadow-border-xs
    utility.tab-bg-group utility.tab-item-active utility.tab-item-hover
    utility.text-inverse utility.text-primary utility.text-secondary utility.text-subdued
  ].freeze

  THEME_COLORS = {
    "color.surface" => [ "#F7F1E7", "#221D16" ],
    "color.surface-hover" => [ "#F1E9D9", "#2A241C" ],
    "color.surface-inset" => [ "#F1E9D9", "#1A140D" ],
    "color.surface-inset-hover" => [ "#E7DCC7", "#2A241C" ],
    "color.container" => [ "#FBF7F0", "#2A241C" ],
    "color.container-hover" => [ "#F7F1E7", "#3B342A" ],
    "color.container-inset" => [ "#F1E9D9", "#1A140D" ],
    "color.container-inset-hover" => [ "#E7DCC7", "#3B342A" ],
    "color.tertiary" => [ "#D9CDB8", "#3B342A" ],
    "color.nav-indicator" => [ "#F2A028", "#F2A028" ],
    "color.link" => [ "#8A5A10", "#DDA761" ],
    "color.destructive" => [ "#A0452A", "#D4664A" ],
    "color.shadow" => [ "rgba(60, 45, 20, 0.08)", "{color.white|8%}" ],
    "utility.text-primary" => [ "#1A1714", "#EDE4D6" ],
    "utility.text-secondary" => [ "#6E6053", "#C79A5E" ],
    "utility.text-subdued" => [ "#9A8B74", "#9A8B74" ],
    "utility.text-inverse" => [ "#FBF7F0", "#1A1714" ]
  }.freeze

  setup do
    @tokens = JSON.parse(File.read(Rails.root.join("design/tokens/sure.tokens.json")))
  end

  test "token leaf paths are unchanged" do
    expected = JSON.parse(File.read(Rails.root.join("test/fixtures/files/oknola/sure_token_paths.json")))
    assert_equal expected, leaf_paths(@tokens).sort
  end

  test "original dark overrides are preserved" do
    DARK_TOKEN_PATHS.each do |path|
      assert token(path).fetch("$extensions").key?("sure.dark"), path
    end
  end

  test "Oknola light and dark token values are canonical" do
    assert_equal "2.1.1", @tokens.fetch("$version")
    THEME_COLORS.each do |path, (light, dark)|
      assert_equal light, token(path).fetch("$value"), path
      assert_equal dark, token(path).fetch("$extensions").fetch("sure.dark"), path
    end

    gray = {
      "25" => "#FBF7F0", "50" => "#F7F1E7", "100" => "#F1E9D9",
      "200" => "#E7DCC7", "300" => "#D9CDB8", "400" => "#9A8B74",
      "500" => "#6E6053", "600" => "#5A4E3C", "700" => "#3B342A",
      "800" => "#2A241C", "900" => "#1A1714"
    }
    gray.each { |step, value| assert_equal value, token("color.gray.#{step}").fetch("$value") }
    assert_equal "'Space Grotesk Variable', 'Helvetica Neue', Helvetica, system-ui, sans-serif", token("font.sans").fetch("$value")
    assert_equal "'JetBrains Mono Variable', ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace", token("font.mono").fetch("$value")

    {
      "xs" => [ "0px 1px 0px 0px", "0px 1px 2px 0px", "0.08" ],
      "sm" => [ "0px 1px 0px 0px", "0px 1px 6px 0px", "0.08" ],
      "md" => [ "0px 4px 8px -2px", "0px 4px 8px -2px", "0.45" ],
      "lg" => [ "0px 12px 16px -4px", "0px 12px 16px -4px", "0.45" ],
      "xl" => [ "0px 20px 24px -4px", "0px 20px 24px -4px", "0.45" ]
    }.each do |step, (light, dark, alpha)|
      assert_equal "#{light} rgba(60, 45, 20, #{alpha})", token("shadow.#{step}").fetch("$value")
      assert_equal "#{dark} {color.white|8%}", token("shadow.#{step}").fetch("$extensions").fetch("sure.dark")
    end
  end

  test "Oknola font imports have licensed local assets" do
    application = File.read(Rails.root.join("app/assets/tailwind/application.css"))
    refute_match(/geist/i, application)
    assert_includes application, '@import "./oknola-fonts.css";'
    fonts = File.read(Rails.root.join("app/assets/tailwind/oknola-fonts.css"))
    space_grotesk_faces = fonts.scan(/@font-face\s*\{[^}]*font-family: 'Space Grotesk Variable';[^}]*\}/)
    assert_equal 2, space_grotesk_faces.size
    space_grotesk_faces.each { |face| assert_includes face, "size-adjust: 98%;" }
    paths = fonts.scan(/url\('\.\/([^']+\.woff2)'\)/).flatten
    assert_equal 4, paths.size
    paths.each { |path| assert File.file?(Rails.root.join("app/assets/fonts", path)), path }
    %w[space_grotesk jetbrains_mono].each do |family|
      assert File.file?(Rails.root.join("app/assets/fonts", family, "OFL.txt")), family
      assert_equal Dir.glob(Rails.root.join("app/assets/fonts", family, "*.woff2")).map { |path| "#{family}/#{File.basename(path)}" }.sort,
        paths.grep(/^#{family}\//).sort
    end
  end

  test "CSS generation is byte-identical and literal utilities retain dark variables" do
    require_node
    path = Rails.root.join("app/assets/tailwind/sure-design-system/_generated.css")
    before = File.binread(path)
    output, status = Open3.capture2e("node", Rails.root.join("bin/tokens.mjs").to_s)
    assert status.success?, output
    assert_equal before, File.binread(path)
    assert_includes before, "@apply text-[#1A1714];"
    assert_includes before, "@apply text-(--utility-text-primary);"
    assert_includes before, "--utility-text-primary: #EDE4D6;"
    refute_match(/@apply #/, before)
  end

  test "generated mobile tokens are current" do
    require_node
    output, status = Open3.capture2e("node", Rails.root.join("mobile/tool/generate_sure_tokens.mjs").to_s, "--check")
    assert status.success?, output
  end

  private
    def token(path)
      @tokens.dig(*path.split("."))
    end

    def leaf_paths(node, path = [])
      return [] unless node.is_a?(Hash)
      return [ path.join(".") ] if node.key?("$value") || node["$type"] == "utility"

      node.flat_map { |key, child| key.start_with?("$") ? [] : leaf_paths(child, path + [ key ]) }
    end

    def require_node
      skip "node is not on PATH" unless ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, "node")) }
    end
end
