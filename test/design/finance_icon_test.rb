# Modified by Cardona Labs, LLC, 2026-11-09, AGPL-3.0
require "test_helper"
require "chunky_png"
require "base64"

class FinanceIconTest < ActiveSupport::TestCase
  test "installed PNG icons have the expected dimensions" do
    {
      "public/favicon-16x16.png" => 16,
      "public/favicon-32x32.png" => 32,
      "public/apple-touch-icon.png" => 180,
      "public/logo-pwa.png" => 512,
      "public/logo-pwa-maskable.png" => 512,
      "public/android-chrome-192x192.png" => 192,
      "public/android-chrome-512x512.png" => 512,
      "public/mstile-150x150.png" => 150,
      "app/assets/images/logo-color.png" => 256
    }.each do |path, size|
      image = ChunkyPNG::Image.from_file(Rails.root.join(path).to_s)
      assert_equal [ size, size ], [ image.width, image.height ], path
    end
  end

  test "iOS and PWA icons are opaque" do
    %w[public/apple-touch-icon.png public/logo-pwa.png public/logo-pwa-maskable.png].each do |path|
      image = ChunkyPNG::Image.from_file(Rails.root.join(path).to_s)
      assert image.pixels.all? { |pixel| ChunkyPNG::Color.a(pixel) == 255 }, path
    end
  end

  test "favicon contains 16, 32 and 48 pixel icons" do
    data = Rails.root.join("public/favicon.ico").binread
    reserved, type, count = data.unpack("v3")
    assert_equal [ 0, 1, 3 ], [ reserved, type, count ]
    sizes = count.times.map do |i|
      width, height, _, _, _, _, length, offset = data.byteslice(6 + i * 16, 16).unpack("CCCCvvVV")
      image = ChunkyPNG::Image.from_blob(data.byteslice(offset, length))
      assert_equal [ width, height ], [ image.width, image.height ]
      [ width, height ]
    end
    assert_equal [ [ 16, 16 ], [ 32, 32 ], [ 48, 48 ] ], sizes.sort
  end

  test "in-app and offline logos embed the rendered mark" do
    mark = Rails.root.join("design/finance-icon/finance-mark-512.png").binread
    %w[app/assets/images/logomark-color.svg app/assets/images/logomark.svg public/logo-offline.svg].each do |path|
      svg = Nokogiri::XML(Rails.root.join(path).read)
      image = svg.at_xpath("//*[local-name()='image']")
      assert image, path
      uri = image["href"]
      assert uri.start_with?("data:image/png;base64,"), path
      assert_equal mark, Base64.strict_decode64(uri.delete_prefix("data:image/png;base64,")), path
    end
  end
end
