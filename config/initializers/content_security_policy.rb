# Be sure to restart your server when you modify this file.
# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.after_initialize do
    posthog = Rails.configuration.x.posthog

    config.content_security_policy do |policy|
      posthog_host = posthog.host if posthog&.api_key.present?
      posthog_loader_host = posthog_host&.sub(%r{\.i\.posthog\.com(?=[:/]|$)}, "-assets.i.posthog.com")

      policy.default_src :self
      policy.base_uri :self
      policy.object_src :none
      policy.frame_ancestors :none
      policy.script_src :self, "https://cdn.plaid.com", *[ posthog_loader_host ].compact
      policy.style_src :self, :unsafe_inline
      policy.img_src :self, :data, :https, :blob
      policy.font_src :self, :data
      policy.frame_src :self, "https://cdn.plaid.com"

      connect_sources = [ "https://*.plaid.com", *[ posthog_host, posthog_loader_host ].compact ]
      policy.connect_src :self, *connect_sources

      policy.report_uri "/oknola/csp_reports"
    end
  end

  config.content_security_policy_nonce_generator = ->(request) do
    next if request.path == "/oknola/csp_reports"
    next unless request.format.html? || request.format.turbo_stream?

    # Keep this nonce stable across sign-in/out; Turbo Drive retains the first document's CSP.
    request.session[:oknola_csp_nonce] ||= SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_report_only = false
end
