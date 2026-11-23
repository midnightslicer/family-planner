require "test_helper"

class PwaTest < ActionDispatch::IntegrationTest
  test "the manifest is served signed out, uncached, with what an install needs" do
    get pwa_manifest_path
    assert_response :success
    assert_equal "/manifest.webmanifest", pwa_manifest_path
    assert_equal "application/manifest+json", response.media_type
    assert_equal "no-cache", response.headers["Cache-Control"]

    manifest = JSON.parse(response.body)
    %w[id name short_name description start_url scope display theme_color background_color icons].each do |key|
      assert manifest[key].present?, "manifest is missing #{key}"
    end
    assert_equal "standalone", manifest["display"]
    assert_equal "/", manifest["scope"]
    assert manifest["start_url"].start_with?("/")
    assert_operator manifest["short_name"].length, :<=, PwaController::SHORT_NAME_MAX

    icons = manifest["icons"].index_by { |icon| [icon["sizes"], icon["purpose"]] }
    assert icons[["192x192", "any"]]
    assert icons[["512x512", "any"]]
    assert icons[["512x512", "maskable"]]
    manifest["icons"].each { |icon| assert Rails.public_path.join(icon["src"].delete_prefix("/")).file?, "#{icon['src']} is missing" }
  end

  test "the manifest names the board" do
    Setting.set("app_name", "The O'Brien family")
    get pwa_manifest_path
    manifest = JSON.parse(response.body)
    assert_equal "The O'Brien family", manifest["name"]
    assert_equal "The O'Brien", manifest["short_name"]
  end

  test "short names fit under an iPhone icon" do
    assert_equal "Home", PwaController.short_name("Home")
    assert_equal "FamilyStatus", PwaController.short_name("Family Status")
    assert_equal "Grandma's", PwaController.short_name("Grandma's lake house board")
    assert_equal "The O'Briens", PwaController.short_name("The O'Briens")
    assert_equal "Supercalifra", PwaController.short_name("Supercalifragilistic")
  end

  test "the service worker is served signed out, uncached, as JavaScript, with a version" do
    get pwa_service_worker_path
    assert_response :success
    assert_equal "/service-worker.js", pwa_service_worker_path
    assert_equal "text/javascript", response.media_type
    assert_equal "no-cache", response.headers["Cache-Control"]
    assert_match(/const VERSION = "\h{12}"/, response.body)
    assert_includes response.body, "/offline.html"
  end

  test "both are served before setup, past the first-run gate" do
    Task.delete_all
    HouseholdMembership.delete_all
    Invitation.delete_all
    User.delete_all
    get pwa_manifest_path
    assert_response :success
    get pwa_service_worker_path
    assert_response :success
  end

  test "the offline page and every icon exist" do
    %w[offline.html icon.svg icon.png icon-192.png icon-512.png icon-maskable-512.png apple-touch-icon.png].each do |file|
      assert Rails.public_path.join(file).file?, "public/#{file} is missing"
    end
  end

  test "app pages link the manifest and set the theme colour" do
    get new_user_session_path
    assert_select "link[rel=manifest][href='/manifest.webmanifest']"
    assert_select "meta[name=theme-color]", 2
    assert_select "meta[name=viewport][content*='viewport-fit=cover']"
    assert_select "link[rel=apple-touch-icon][href='/apple-touch-icon.png']"
  end

  test "the wall doesn't: it's a bookmark, not an install" do
    sign_in users(:admin)
    get wall_path(households(:smiths).slug)
    assert_response :success
    assert_select "link[rel=manifest]", 0
  end
end
