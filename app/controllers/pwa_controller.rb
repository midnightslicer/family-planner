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

  # Copied from the light token block in application.css (--surface for the
  # status bar, --bg for the splash screen) and the brand --accent. The
  # manifest can't read CSS, so these are the one place the hexes repeat.
  THEME_COLOR = "#ffffff".freeze
  BACKGROUND_COLOR = "#f4f6f9".freeze

  before_action :no_cache

  def manifest
    render json: manifest_json, content_type: "application/manifest+json"
  end

  def service_worker
    @version = worker_version
    render template: "pwa/service-worker", formats: [:js], layout: false, content_type: "text/javascript"
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
      theme_color: THEME_COLOR,
      background_color: BACKGROUND_COLOR,
      icons: [
        { src: "/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
        { src: "/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" }
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
      break kept if [*kept, word].join(" ").length > SHORT_NAME_MAX

      kept << word
    end
    words.any? ? words.join(" ") : name[0, SHORT_NAME_MAX]
  end

  # Changes whenever the worker or the offline page it precaches changes, so
  # the new worker installs and replaces the old cache.
  def worker_version
    files = [Rails.root.join("public/offline.html"), Rails.root.join("app/views/pwa/service-worker.js.erb")]
    Digest::SHA256.hexdigest(files.map { |file| File.read(file) }.join)[0, 12]
  end
end
