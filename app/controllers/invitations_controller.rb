# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
class InvitationsController < ApplicationController
  skip_authentication only: :accept
  def new
    @invitation = Invitation.new
  end

  def create
    unless Current.user.admin?
      flash[:alert] = t(".failure")
      redirect_to settings_profile_path
      return
    end

    @invitation = Current.family.invitations.build(invitation_params)
    @invitation.inviter = Current.user

    if save_invitation
      # Oknola: never accept on the invitee's behalf. An existing user joins only
      # by opening the invitation link themselves (accept_choice), and the inviter
      # sees the same answer whether or not the email has an account.
      InvitationMailer.invite_email(@invitation).deliver_later unless self_hosted?
      flash[:notice] = t(".success")
    else
      flash[:alert] = t(".failure")
    end

    redirect_to settings_profile_path
  end

  def accept
    @invitation = Invitation.find_by!(token: params[:id])

    if @invitation.pending?
      render :accept_choice, layout: "auth"
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def destroy
    unless Current.user.admin?
      flash[:alert] = t("invitations.destroy.not_authorized")
      redirect_to settings_profile_path
      return
    end

    @invitation = Current.family.invitations.find(params[:id])

    if @invitation.destroy
      flash[:notice] = t("invitations.destroy.success")
    else
      flash[:alert] = t("invitations.destroy.failure")
    end

    redirect_to settings_profile_path
  end

  private

    def invitation_params
      params.require(:invitation).permit(:email, :role)
    end

    # Persist the invitation, treating a raced partial-unique-index violation as
    # an ordinary save failure. A concurrent double-submit can still slip between
    # the `no_duplicate_pending_invitation_in_family` validation and the INSERT.
    # Scoping the rescue to the save alone keeps any later write in #create from
    # silently swallowing a genuine RecordNotUnique.
    def save_invitation
      @invitation.save
    rescue ActiveRecord::RecordNotUnique
      false
    end
end
