// ---- Monochrome theme for the Firefox UI only (websites untouched) ----
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true); // load chrome/*.css
user_pref("extensions.activeThemeID", "default-theme@mozilla.org");
user_pref("browser.theme.toolbar-theme", 0);                 // dark toolbars/menus
user_pref("widget.gtk.rounded-bottom-corners.enabled", false);
user_pref("browser.tabs.inTitlebar", 0);                     // no CSD buttons under Hyprland
