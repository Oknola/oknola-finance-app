# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
# Signs Oknola users in to Finance without a Finance password.
#
# POST /oknola/handoff is server to server: the Oknola server, holding the
# shared secret, names the Oknola user (sub, email, preferences) and gets back
# a one-time code. GET /oknola/session?code= is opened by the Oknola client:
# it redeems the code once and signs the browser in. Oknola is the identity
# source, so the identity is keyed by the Oknola sub and the email follows it.
module Oknola
  class HandoffController < ApplicationController
    include Oknola::SecretAuthentication

    PROVIDER = "oknola".freeze
    CODE_TTL = 60.seconds
    CODE_CACHE_PREFIX = "oknola_handoff:".freeze
    THEMES = %w[light dark system].freeze
    # An in-app path only: one leading "/", never "//" (protocol-relative),
    # no backslashes, whitespace or control characters.
    SAFE_ROUTE = %r{\A/(?![/\\])[^\\\x00-\x20\x7F]*\z}

    skip_authentication only: %i[create show]
    # The handoff is a server-to-server JSON call authenticated by the shared
    # secret; it carries no browser session to forge.
    skip_forgery_protection only: :create
    before_action :require_oknola_secret!, only: :create

    def create
      sub = params[:sub].to_s
      email = params[:email].to_s.strip.downcase

      if sub.blank? || !email.match?(URI::MailTo::EMAIL_REGEXP)
        render json: { error: "invalid" }, status: :unprocessable_entity
        return
      end

      # A super admin removed this identity: it must not come back.
      return render_gone if SsoIdentityBlock.blocked?(provider: PROVIDER, uid: sub)

      user = find_or_provision_user(sub, email)
      return render_gone unless user.active?

      user.update!(email: email) unless user.email == email

      code = SecureRandom.urlsafe_base64(32)
      Rails.cache.write(code_cache_key(code), { user_id: user.id, route: safe_route(params[:route]) }, expires_in: CODE_TTL)

      response.headers["Cache-Control"] = "no-store"
      render json: { code: code }
    rescue ActiveRecord::RecordInvalid => e
      # The email belongs to a Finance user Oknola does not own: never merged.
      if e.record.is_a?(User) && e.record.errors.of_kind?(:email, :taken)
        render json: { error: "email_conflict" }, status: :conflict
      else
        render json: { error: "invalid" }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique => e
      if e.message.include?("index_users_on_email")
        render json: { error: "email_conflict" }, status: :conflict
      else
        render json: { error: "invalid" }, status: :unprocessable_entity
      end
    end

    def show
      code = params[:code].to_s
      data = code.present? ? Rails.cache.read(code_cache_key(code)) : nil
      # Atomically claim the code: only the request whose delete removes the
      # entry may proceed, so a replayed or concurrent redeem fails.
      claimed = data.present? && Rails.cache.delete(code_cache_key(code))
      return sign_in_failed unless claimed

      data = data.with_indifferent_access
      user = User.find_by(id: data[:user_id])
      return sign_in_failed unless user&.active?

      csp_nonce = session[:oknola_csp_nonce]
      reset_session
      session[:oknola_csp_nonce] = csp_nonce if csp_nonce.present?

      if user.otp_required?
        session[:mfa_user_id] = user.id
        session[:oknola_embedded] = true
        redirect_to verify_mfa_path
        return
      end

      return sign_in_failed unless create_session_for(user)

      session[:oknola_embedded] = true
      # The route was bound by the Oknola server when the code was minted and
      # checked then; checking again keeps a tampered cache entry in-app.
      redirect_to safe_route(data[:route])
    end

    private
      # Keyed by a digest so the cache (and its logs) never hold a live code.
      def code_cache_key(code)
        "#{CODE_CACHE_PREFIX}#{Digest::SHA256.hexdigest(code)}"
      end

      def render_gone
        render json: { error: "user_inactive" }, status: :gone
      end

      def sign_in_failed
        redirect_to new_session_path, alert: t("sessions.openid_connect.failed")
      end

      def safe_route(value)
        value.is_a?(String) && value.match?(SAFE_ROUTE) ? value : "/"
      end

      def find_or_provision_user(sub, email)
        identity = OidcIdentity.find_by(provider: PROVIDER, uid: sub)
        return identity.user if identity

        provision_user!(sub, email)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # A concurrent handoff for the same sub may have won the race.
        OidcIdentity.find_by(provider: PROVIDER, uid: sub)&.user || raise
      end

      def provision_user!(sub, email)
        ActiveRecord::Base.transaction do
          # Serializes with Sure's first-user logic; an Oknola user is always
          # a family admin, never the instance super admin.
          User.lock_first_user_role!

          family = Family.create!(family_attributes)
          user = family.users.create!(
            email: email,
            skip_password_validation: true,
            role: :admin,
            theme: THEMES.include?(params[:theme].to_s) ? params[:theme].to_s : "system",
            onboarded_at: Time.current,
            set_onboarding_preferences_at: Time.current
          )
          user.oidc_identities.create!(provider: PROVIDER, uid: sub)
          user
        end
      end

      def family_attributes
        country = params[:country].to_s.upcase
        country = "US" unless country.match?(/\A[A-Z]{2}\z/) && ISO3166::Country.new(country)
        locale = params[:locale].to_s
        locale = "en" unless I18n.available_locales.map(&:to_s).include?(locale)
        timezone = params[:time_zone].to_s

        {
          currency: Family.default_currency_for_country(country),
          locale: locale,
          timezone: ActiveSupport::TimeZone[timezone].present? ? timezone : nil,
          country: country
        }
      end
  end
end
