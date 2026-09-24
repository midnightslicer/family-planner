# Content Security Policy. Everything the app loads is same-origin: esbuild
# bundles the JS, Propshaft serves the CSS, and the 2FA QR code is inline SVG
# rendered on the server. Inline *scripts* are never allowed.
#
# style-src keeps 'unsafe-inline' because person cards and swatches carry
# their colour as an inline custom property (style="--user-color: ...").
# Values are validated hex colours, and CSS can't run script.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.img_src     :self, :data
    policy.font_src    :self
    # Action Cable's websocket; 'self' covers ws(s) in current browsers, the
    # explicit origin helps older Safari.
    policy.connect_src :self, -> { "#{request.ssl? ? 'wss' : 'ws'}://#{request.host_with_port}" }
    policy.object_src  :none
    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :self
  end
end
