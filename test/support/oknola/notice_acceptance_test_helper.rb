# frozen_string_literal: true

# Users a test creates itself (not fixtures) accept the early-access notice
# when the test signs them in, so upstream tests keep testing their own page
# instead of the notice. Tests of the notice remove the acceptance after
# signing in, or sign in through the Oknola handoff.
module OknolaNoticeAcceptanceTestHelper
  def sign_in(user)
    Oknola::Acceptance.accept_early_access!(user) if user.respond_to?(:persisted?) && user.persisted?
    super
  end
end

ActiveSupport::TestCase.prepend(OknolaNoticeAcceptanceTestHelper)
