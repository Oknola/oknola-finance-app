require "test_helper"

class Oknola::AccountsControllerTest < ActionDispatch::IntegrationTest
  SECRET = "test-oknola-handoff-secret-0123456789abcdef".freeze
  SUB = "4f1c2a9e-0000-4000-8000-00000000d1d1".freeze

  setup do
    @original_secret = ENV["OKNOLA_HANDOFF_SECRET"]
    ENV["OKNOLA_HANDOFF_SECRET"] = SECRET

    post oknola_handoff_path,
      params: { sub: SUB, email: "purge.me@example.com", country: "US" },
      headers: auth_headers,
      as: :json
    assert_response :success

    @user = OidcIdentity.find_by!(provider: "oknola", uid: SUB).user
    @family = @user.family
    @account = @family.accounts.create!(
      name: "Checking", balance: 100, currency: "USD", accountable: Depository.new(subtype: "checking")
    )
  end

  teardown do
    ENV["OKNOLA_HANDOFF_SECRET"] = @original_secret
  end

  test "rejects a wrong secret and deletes nothing" do
    assert_no_difference [ "User.count", "Family.count", "Account.count" ] do
      delete oknola_account_path(sub: SUB), headers: auth_headers("wrong")
    end

    assert_response :unauthorized
  end

  test "rejects every call when the secret is not configured" do
    ENV["OKNOLA_HANDOFF_SECRET"] = ""

    delete oknola_account_path(sub: SUB), headers: { "Authorization" => "Bearer " }

    assert_response :unauthorized
    assert User.exists?(@user.id)
  end

  test "ends access at once and purges the family, accounts, tags and identity" do
    tag_ids = @family.tags.pluck(:id)
    assert_equal 2, tag_ids.size
    @user.sessions.create!

    assert_enqueued_with(job: UserPurgeJob, args: [ @user ]) do
      delete oknola_account_path(sub: SUB), headers: auth_headers
    end

    assert_response :accepted
    assert_not @user.reload.active?
    assert_empty @user.sessions
    assert_not OidcIdentity.exists?(provider: "oknola", uid: SUB)

    perform_enqueued_jobs only: UserPurgeJob

    assert_not User.exists?(@user.id)
    assert_not Family.exists?(@family.id)
    assert_not Account.exists?(@account.id)
    assert_not Tag.exists?(id: tag_ids)
  end

  test "purges in the request when the job cannot be enqueued" do
    UserPurgeJob.stubs(:perform_later).raises(RedisClient::CannotConnectError.new("redis down"))

    delete oknola_account_path(sub: SUB), headers: auth_headers

    assert_response :no_content
    assert_not User.exists?(@user.id)
    assert_not Family.exists?(@family.id)
    assert_not Account.exists?(@account.id)
  end

  test "keeps the family when another member remains" do
    other = @family.users.create!(email: "stays@example.com", skip_password_validation: true, role: :admin, onboarded_at: Time.current)

    delete oknola_account_path(sub: SUB), headers: auth_headers
    assert_response :accepted
    perform_enqueued_jobs only: UserPurgeJob

    assert_not User.exists?(@user.id)
    assert Family.exists?(@family.id)
    assert User.exists?(other.id)
  end

  test "an unknown sub is already purged" do
    assert_no_difference [ "User.count", "Family.count" ] do
      delete oknola_account_path(sub: "no-such-sub"), headers: auth_headers
    end

    assert_response :no_content
  end

  test "a second delete of the same sub is 204" do
    delete oknola_account_path(sub: SUB), headers: auth_headers
    assert_response :accepted

    delete oknola_account_path(sub: SUB), headers: auth_headers

    assert_response :no_content
  end

  private
    def auth_headers(secret = SECRET)
      { "Authorization" => "Bearer #{secret}" }
    end
end
