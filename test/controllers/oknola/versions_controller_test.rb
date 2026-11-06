require "test_helper"

class Oknola::VersionsControllerTest < ActionDispatch::IntegrationTest
  test "returns the commit without a session" do
    sha = "0123456789abcdef0123456789abcdef01234567"
    Sure.stubs(:commit_sha).returns(sha)
    # Match the profiler's production authorization mode.
    Rack::MiniProfiler.config.stubs(:authorization_mode).returns(:allow_authorized)

    get oknola_version_path

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_equal sha, response.body
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
  end
end
