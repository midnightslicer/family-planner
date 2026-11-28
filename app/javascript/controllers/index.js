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

import PushController from "./push_controller"
application.register("push", PushController)

import PushNudgeController from "./push_nudge_controller"
application.register("push-nudge", PushNudgeController)

import PushSyncController from "./push_sync_controller"
application.register("push-sync", PushSyncController)

import ToastController from "./toast_controller"
application.register("toast", ToastController)

import PhotoUploadController from "./photo_upload_controller"
application.register("photo-upload", PhotoUploadController)

import QuickAddController from "./quick_add_controller"
application.register("quick-add", QuickAddController)

import MoveBoardController from "./move_board_controller"
application.register("move-board", MoveBoardController)

import WallFitController from "./wall_fit_controller"
application.register("wall-fit", WallFitController)

import WorkWeekController from "./work_week_controller"
application.register("work-week", WorkWeekController)

import PickerController from "./picker_controller"
application.register("picker", PickerController)

import PasskeyLoginController from "./passkey_login_controller"
application.register("passkey-login", PasskeyLoginController)

import PasskeyRegisterController from "./passkey_register_controller"
application.register("passkey-register", PasskeyRegisterController)

import PasskeySignupController from "./passkey_signup_controller"
application.register("passkey-signup", PasskeySignupController)

import WallDriftController from "./wall_drift_controller"
application.register("wall-drift", WallDriftController)

import TabBarController from "./tab_bar_controller"
application.register("tab-bar", TabBarController)

import ChangelogController from "./changelog_controller"
application.register("changelog", ChangelogController)
