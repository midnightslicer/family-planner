module ThemeHelper
  # The signed-in person's colour tokens (ColorTheme) as a <style> block,
  # printed after the stylesheet so it overrides application.css's defaults
  # for both themes. Nothing for signed-out pages: they keep the defaults.
  def theme_tokens_tag(user = current_theme_user)
    theme = user && ColorTheme.for(user.color)
    return unless theme

    tag.style(theme.css.html_safe, id: "theme-tokens") # rubocop:disable Rails/OutputSafety -- every value is a computed hex/rgba
  end

  # The installed app's title bar colour, light or dark.
  def theme_surface(scheme, user = current_theme_user)
    theme = user && ColorTheme.for(user.color)
    theme ? theme.surface(scheme) : { light: "#ffffff", dark: "#171d26" }.fetch(scheme)
  end

  private

  def current_theme_user
    current_user if respond_to?(:user_signed_in?) && user_signed_in?
  end
end
