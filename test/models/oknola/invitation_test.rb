# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
require "test_helper"

class Oknola::InvitationTest < ActiveSupport::TestCase
  test "a member cannot create an invitation" do
    invitation = families(:dylan_family).invitations.build(
      email: "invitee@example.com", role: "member", inviter: users(:family_member)
    )

    assert_not invitation.save
    assert_includes invitation.errors[:inviter], I18n.t("invitations.errors.inviter_not_admin")
  end

  test "an invitation without an inviter fails validation" do
    invitation = families(:dylan_family).invitations.build(email: "invitee@example.com", role: "member")

    assert_not invitation.valid?
    assert_includes invitation.errors[:inviter], I18n.t("invitations.errors.inviter_not_admin")
  end

  test "an admin can create an invitation" do
    invitation = families(:dylan_family).invitations.create!(
      email: "invitee@example.com", role: "member", inviter: users(:family_admin)
    )

    assert invitation.persisted?
  end

  test "an invitation can be accepted after the inviter is demoted" do
    invitee = users(:empty)
    inviter = users(:family_admin)
    invitation = families(:dylan_family).invitations.create!(
      email: invitee.email, role: "member", inviter: inviter
    )
    inviter.update!(role: "member")

    assert invitation.accept_for(invitee)
    assert invitation.reload.accepted_at.present?
    assert_equal invitation.family_id, invitee.reload.family_id
    assert_equal "member", invitee.role
  end
end
