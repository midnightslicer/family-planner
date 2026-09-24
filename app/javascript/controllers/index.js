// Register every Stimulus controller here (esbuild bundles this file; there
// is no import map, so new controllers must be added by hand).

import { application } from "./application"

import AutoRefreshController from "./auto_refresh_controller"
application.register("auto-refresh", AutoRefreshController)

import AutosubmitController from "./autosubmit_controller"
application.register("autosubmit", AutosubmitController)

import ClipboardController from "./clipboard_controller"
application.register("clipboard", ClipboardController)

import NotificationController from "./notification_controller"
application.register("notification", NotificationController)

import NotificationsController from "./notifications_controller"
application.register("notifications", NotificationsController)

import PasskeyLoginController from "./passkey_login_controller"
application.register("passkey-login", PasskeyLoginController)

import PasskeyRegisterController from "./passkey_register_controller"
application.register("passkey-register", PasskeyRegisterController)

import PasskeySignupController from "./passkey_signup_controller"
application.register("passkey-signup", PasskeySignupController)
