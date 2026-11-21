// Register every Stimulus controller here (esbuild bundles this file; there
// is no import map, so new controllers must be added by hand).

import { application } from "./application"

import AutoRefreshController from "./auto_refresh_controller"
application.register("auto-refresh", AutoRefreshController)

import AutosubmitController from "./autosubmit_controller"
application.register("autosubmit", AutosubmitController)

import ColorPickerController from "./color_picker_controller"
application.register("color-picker", ColorPickerController)

import CelebrateController from "./celebrate_controller"
application.register("celebrate", CelebrateController)

import ClipboardController from "./clipboard_controller"
application.register("clipboard", ClipboardController)

import MenuController from "./menu_controller"
application.register("menu", MenuController)

import NotificationController from "./notification_controller"
application.register("notification", NotificationController)

import NotificationsController from "./notifications_controller"
application.register("notifications", NotificationsController)

import PhotoUploadController from "./photo_upload_controller"
application.register("photo-upload", PhotoUploadController)

import PickerController from "./picker_controller"
application.register("picker", PickerController)

import PasskeyLoginController from "./passkey_login_controller"
application.register("passkey-login", PasskeyLoginController)

import PasskeyRegisterController from "./passkey_register_controller"
application.register("passkey-register", PasskeyRegisterController)

import PasskeySignupController from "./passkey_signup_controller"
application.register("passkey-signup", PasskeySignupController)
