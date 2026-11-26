# The two files that make the app installable: the web app manifest and the
# service worker. Our own controller rather than Rails::PwaController because
# the manifest names the app (AppSettings.app_name).
#
# Inherits ActionController::Base directly, so none of the app's filters run:
# no first-run gate, no sign-in, no household. A browser fetches both files
# on its own (before setup, signed out, from the install prompt) and must
# always get them.
class PwaController < ActionController::Base
  # GET requests answered with JavaScript trip Rails' cross-origin script
  # check; the worker is fetched by the browser itself, never embedded.
  skip_forgery_protection

  # iOS cuts the name under the Home Screen icon at about 12 characters.
  SHORT_NAME_MAX = 12

  # Copied from the token blocks in application.css (--surface for the
  # system bars, --bg for the splash screen), light then dark. The manifest
  # can't read CSS, so these are the one place the hexes repeat. Signed in,
  # the person's own theme (ColorTheme) is used instead.
  THEME_COLORS = { light: "#ffffff", dark: "#171d26" }.freeze
  BACKGROUND_COLORS = { light: "#f4f6f9", dark: "#0f141b" }.freeze
  # The wall is always dark: body.kiosk's --bg in kiosk.css.
  WALL_COLOR = "#0d1117".freeze
  SLUG = /\A[a-z0-9_-]{1,60}\z/

  before_action :no_cache

  # Android paints an installed app's system bars (the gesture bar at the
  # bottom too) in the manifest's theme_color, not the page's, so it carries
  # the colours you see: your theme, in the scheme your device is in (the
  # "scheme" cookie, set by application.js; the layout links the manifest
  # with credentials so the cookie comes along). Varies with who asks, so
  # never cached.
  def manifest
    response.headers["Cache-Control"] = "no-store"
    render json: manifest_json, content_type: "application/manifest+json"
  end

  # GET /h/:slug/manifest.webmanifest: a household's wall as an app of its
  # own, so a wall tablet can install it, open it full screen and reopen it
  # from its icon. Scoped to that wall, so it never competes with the main
  # app for links. It needs no data: the slug is already in the address, and
  # the household's name is only filled in for a signed-in member (the
  # layout links it with crossorigin="use-credentials" so the cookie comes
  # along); anyone else gets the app's name. Unknown slugs aren't revealed.
  def wall_manifest
    slug = params[:slug].to_s
    return head(:not_found) unless slug.match?(SLUG)

    response.headers["Cache-Control"] = "no-store" # varies with who asks: never cached anywhere
    render json: wall_manifest_json(slug), content_type: "application/manifest+json"
  end

  def service_worker
    @version = worker_version
    @app_name = AppSettings.app_name
    render template: "pwa/service-worker", formats: [ :js ], layout: false, content_type: "text/javascript"
  end

  private

  # Updates must reach browsers (and get past Thruster's cache) on the next
  # visit; the browser revalidates the worker itself, but not the manifest.
  def no_cache
    response.headers["Cache-Control"] = "no-cache"
  end

  def manifest_json
    name = AppSettings.app_name
    {
      id: "/",
      name: name,
      short_name: self.class.short_name(name),
      description: "Who's busy, who's free, and where everyone (pets too) is right now. Your family's day at a glance.",
      start_url: "/?source=pwa",
      scope: "/",
      display: "standalone",
      theme_color: theme_color,
      background_color: background_color,
      icons: [
        { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
        { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
      ]
    }
  end

  def scheme = cookies[:scheme] == "dark" ? :dark : :light

  def theme
    return @theme if defined?(@theme)

    @theme = current_user && ColorTheme.for(current_user.color)
  end

  def theme_color = theme ? theme.surface(scheme) : THEME_COLORS.fetch(scheme)

  def background_color = theme ? theme.public_send(scheme).fetch("--bg") : BACKGROUND_COLORS.fetch(scheme)

  def wall_manifest_json(slug)
    household = current_user&.households&.find_by(slug: slug)
    name = household&.name || AppSettings.app_name
    {
      id: "/h/#{slug}",
      name: "#{name} wall",
      short_name: self.class.short_name(name),
      description: "The family board for a screen on the wall: who's where, and what everyone's up to.",
      start_url: "/h/#{slug}",
      scope: "/h/#{slug}",
      display: "fullscreen",
      display_override: [ "fullscreen", "standalone" ],
      theme_color: WALL_COLOR,
      background_color: WALL_COLOR,
      icons: [
        { src: "/icon-wall-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
        { src: "/icon-wall-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icon-wall-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
      ]
    }
  end

  # "Family Status" → "FamilyStatus", "The O'Brien family" → "The O'Brien";
  # a long single word is cut.
  def self.short_name(name)
    return name if name.length <= SHORT_NAME_MAX

    squeezed = name.delete(" ")
    return squeezed if squeezed.length <= SHORT_NAME_MAX

    words = name.split.each_with_object([]) do |word, kept|
      break kept if [ *kept, word ].join(" ").length > SHORT_NAME_MAX

      kept << word
    end
    words.any? ? words.join(" ") : name[0, SHORT_NAME_MAX]
  end

  # Changes whenever the worker or the offline page it precaches changes, so
  # the new worker installs and replaces the old cache.
  def worker_version
    files = [ Rails.root.join("public/offline.html"), Rails.root.join("app/views/pwa/service-worker.js.erb") ]
    Digest::SHA256.hexdigest(files.map { |file| File.read(file) }.join)[0, 12]
  end
end
