import { Controller } from "@hotwired/stimulus"

const INSTALL_DISMISS_KEY = "notae-pwa-install-dismissed-at"
const IOS_DISMISS_KEY = "notae-pwa-ios-dismissed-at"
const PUSH_DISMISS_KEY = "notae-pwa-push-dismissed-at"
const PUSH_TEST_SENT_KEY = "notae-pwa-push-test-sent-at"
const PUSH_TEST_DELIVERED_KEY = "notae-pwa-push-test-delivered-at"
const PUSH_BANNER_CONFIRMED_KEY = "notae-pwa-push-banner-confirmed-at"
const PUSH_BANNER_MISSED_KEY = "notae-pwa-push-banner-missed-at"
const PUSH_READINESS_COLLAPSED_KEY = "notae-pwa-push-readiness-collapsed"
const DISMISS_WINDOW_MS = 7 * 24 * 60 * 60 * 1000
const NETWORK_TOAST_MS = 2600

export default class extends Controller {
  static targets = [
    "installPrompt",
    "iosPrompt",
    "offlineBanner",
    "networkToast",
    "pushPrompt",
    "pushSettingsToggle",
    "pushSettingsStateLabel",
    "pushSettingsStatus",
    "pushSettingsTestButton",
    "pushSettingsFeedback",
    "pushSettingsReadinessBadge",
    "pushReadinessCard",
    "pushReadinessPermissionPill",
    "pushReadinessPermissionDetail",
    "pushReadinessSubscriptionPill",
    "pushReadinessSubscriptionDetail",
    "pushReadinessDeliveryPill",
    "pushReadinessDeliveryDetail",
    "pushReadinessBannerPill",
    "pushReadinessBannerDetail",
    "pushBannerActions",
    "pushBannerSeenButton",
    "pushBannerMissedButton"
  ]
  static values = {
    authenticated: Boolean,
    webPushPublicKey: String
  }

  connect() {
    this.deferredPrompt = null
    this.devicePushSubscribed = false
    this.networkToastTimeout = null
    this.pushUiPending = false
    this.pushTestPending = false
    this.pushSettingsFeedbackTone = "neutral"
    this.beforeInstallPromptHandler = (event) => this.handleBeforeInstallPrompt(event)
    this.appInstalledHandler = () => this.handleAppInstalled()
    this.onlineHandler = () => this.refreshNetworkState()
    this.offlineHandler = () => this.refreshNetworkState()
    this.submitHandler = (event) => this.handleDocumentSubmit(event)
    this.clickHandler = (event) => this.handleDocumentClick(event)
    this.turboLoadHandler = () => this.refreshNetworkState()
    this.serviceWorkerMessageHandler = (event) => this.handleServiceWorkerMessage(event)

    window.addEventListener("beforeinstallprompt", this.beforeInstallPromptHandler)
    window.addEventListener("appinstalled", this.appInstalledHandler)
    window.addEventListener("online", this.onlineHandler)
    window.addEventListener("offline", this.offlineHandler)
    document.addEventListener("submit", this.submitHandler, true)
    document.addEventListener("click", this.clickHandler, true)
    document.addEventListener("turbo:load", this.turboLoadHandler)
    navigator.serviceWorker?.addEventListener?.("message", this.serviceWorkerMessageHandler)

    if (!this.authenticatedValue) this.clearPrivateCaches()

    this.refreshNetworkState()
    this.syncPushReadinessCardState()
    this.syncPushSubscription().catch(() => {}).finally(() => this.refreshPushUi())
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.beforeInstallPromptHandler)
    window.removeEventListener("appinstalled", this.appInstalledHandler)
    window.removeEventListener("online", this.onlineHandler)
    window.removeEventListener("offline", this.offlineHandler)
    document.removeEventListener("submit", this.submitHandler, true)
    document.removeEventListener("click", this.clickHandler, true)
    document.removeEventListener("turbo:load", this.turboLoadHandler)
    navigator.serviceWorker?.removeEventListener?.("message", this.serviceWorkerMessageHandler)
    this.clearNetworkToast()
  }

  install(event) {
    event.preventDefault()
    if (!this.deferredPrompt) return

    const prompt = this.deferredPrompt
    this.deferredPrompt = null

    prompt.prompt()
    prompt.userChoice.then((choice) => {
      if (choice?.outcome !== "accepted") this.rememberDismissal(INSTALL_DISMISS_KEY)
      this.syncInstallPrompts()
    })
  }

  dismissInstall(event) {
    event.preventDefault()
    this.rememberDismissal(INSTALL_DISMISS_KEY)
    this.syncInstallPrompts()
  }

  dismissIosPrompt(event) {
    event.preventDefault()
    this.rememberDismissal(IOS_DISMISS_KEY)
    this.syncInstallPrompts()
  }

  openInstallExperience(event) {
    event.preventDefault()
    window.localStorage.removeItem(INSTALL_DISMISS_KEY)
    window.localStorage.removeItem(IOS_DISMISS_KEY)
    this.syncInstallPrompts()

    if (this.deferredPrompt) {
      this.install(event)
      return
    }

    const prompt = this.hasIosPromptTarget ? this.iosPromptTarget : (this.hasInstallPromptTarget ? this.installPromptTarget : null)
    if (!prompt) return

    prompt.hidden = false
    prompt.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  enablePush(event) {
    event.preventDefault()
    this.subscribeToPushNotifications().catch(() => {
      this.showNetworkToast("Push notifications could not be enabled yet.")
      this.refreshPushUi()
    })
  }

  togglePush(event) {
    event.preventDefault()
    if (this.pushUiPending) return

    const state = this.pushSettingsState()
    if (state.disabled) {
      this.showNetworkToast(state.message)
      return
    }

    this.pushUiPending = true
    this.refreshPushUi()

    const operation = state.checked ? this.disablePushNotifications() : this.subscribeToPushNotifications()
    operation.catch(() => {
      this.showNetworkToast("Push notifications could not be updated yet.")
    }).finally(() => {
      this.pushUiPending = false
      this.refreshPushUi()
    })
  }

  dismissPush(event) {
    event.preventDefault()
    this.rememberDismissal(PUSH_DISMISS_KEY)
    this.syncPushPrompt()
  }

  async sendTestPush(event) {
    event.preventDefault()
    if (this.pushUiPending || this.pushTestPending) return

    const state = this.pushSettingsState()
    if (state.disabled || !state.checked) {
      this.setPushSettingsFeedback("Enable push notifications on this device first.", "error")
      this.showNetworkToast("Enable push notifications on this device first.")
      return
    }

    this.setPushSettingsFeedback("Checking this device subscription…", "pending")

    await this.syncPushSubscription().catch(() => {})
    this.refreshPushUi()

    const subscription = await this.currentPushSubscription()
    if (!subscription?.endpoint) {
      this.setPushSettingsFeedback("This browser does not have an active push subscription.", "error")
      this.showNetworkToast("This device does not have an active push subscription.")
      return
    }

    const path = this.testPushPathFor(event.currentTarget)
    if (!path) {
      this.setPushSettingsFeedback("The test push endpoint is missing on this page.", "error")
      this.showNetworkToast("The test push endpoint is missing.")
      return
    }

    this.pushTestPending = true
    this.markPushTestAttempted()
    this.refreshPushUi()

    try {
      let payload
      let response = await this.sendTestPushRequest(path, subscription.endpoint)
      payload = await response.json().catch(() => ({}))

      if (!response.ok && payload.error_code === "stale_subscription") {
        this.setPushSettingsFeedback("Refreshing this device subscription…", "pending")
        const refreshedSubscription = await this.rebuildPushSubscription()
        response = await this.sendTestPushRequest(path, refreshedSubscription.endpoint)
        payload = await response.json().catch(() => ({}))
      }

      if (!response.ok) throw new Error(payload.error || "Test push could not be sent.")

      if (payload.current_device_delivered) {
        this.markPushTestDelivered()
        this.setPushSettingsFeedback("Test push reached this browser. Confirm whether you also saw the device banner.", "pending")
      } else {
        this.setPushSettingsFeedback("Test push was sent to your signed-in devices, but this browser did not confirm delivery.", "error")
      }

      this.showNetworkToast(payload.message || "Test push sent.")
    } catch (error) {
      this.setPushSettingsFeedback(error.message || "Test push could not be sent.", "error")
      this.showNetworkToast(error.message || "Test push could not be sent.")
    } finally {
      this.pushTestPending = false
      this.refreshPushUi()
    }
  }

  refreshNetworkState() {
    const offline = !window.navigator.onLine

    document.body.classList.toggle("notae-pwa-is-offline", offline)
    document.body.classList.toggle("notae-pwa-is-standalone", this.standaloneMode())
    this.toggleTargetVisibility("offlineBanner", !offline)
    this.syncOnlineOnlyControls(offline)
    this.syncInstallPrompts()
    this.syncPushPrompt()
    this.refreshPushUi()
    if (!offline) this.syncPushSubscription().catch(() => {})
  }

  handleBeforeInstallPrompt(event) {
    event.preventDefault()
    this.deferredPrompt = event
    this.syncInstallPrompts()
  }

  handleAppInstalled() {
    this.deferredPrompt = null
    window.localStorage.removeItem(INSTALL_DISMISS_KEY)
    this.syncInstallPrompts()
  }

  handleDocumentSubmit(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return

    if (form.dataset.pwaClearPrivateCache === "true") {
      this.detachPushSubscription({ keepBrowserSubscription: true }).catch(() => {})
      this.clearPrivateCaches()
    }

    if (window.navigator.onLine) return
    if (!this.onlineOnlyForm(form)) return

    event.preventDefault()
    this.showNetworkToast("Reconnect to save changes or run sync actions.")
  }

  handleDocumentClick(event) {
    const link = event.target.closest("a[data-turbo-method]")
    if (link?.closest("form[data-pwa-clear-private-cache='true']")) return

    if (!window.navigator.onLine && link instanceof HTMLAnchorElement) {
      event.preventDefault()
      this.showNetworkToast("Reconnect to complete this action.")
    }
  }

  handleServiceWorkerMessage(event) {
    if (event.data?.type !== "notae:push-received") return

    this.handleIncomingPushReceipt(event.data.payload || {})
  }

  handleIncomingPushReceipt(payload) {
    if (payload.notificationType === "test_push") {
      this.markPushTestDelivered()
      this.setPushSettingsFeedback("Test push reached this browser. Confirm whether you also saw the device banner.", "pending")
      this.refreshPushUi()
    }

    window.dispatchEvent(new CustomEvent("notae:push-received", { detail: payload }))
    this.showIncomingPushToast(payload)
  }

  showIncomingPushToast(payload) {
    const title = payload?.title?.toString().trim() || "Notae"
    const body = payload?.body?.toString().trim() || ""
    this.showNetworkToast(body.length > 0 ? `${title} · ${body}` : title)
  }

  syncInstallPrompts() {
    const showAndroidPrompt = this.shouldShowInstallPrompt()
    const showIosPrompt = this.shouldShowIosPrompt()

    this.toggleTargetVisibility("installPrompt", !showAndroidPrompt)
    this.toggleTargetVisibility("iosPrompt", !showIosPrompt)
  }

  syncPushPrompt() {
    this.toggleTargetVisibility("pushPrompt", !this.shouldShowPushPrompt())
  }

  refreshPushUi() {
    if (!this.hasPushSettingsToggleTarget && !this.hasPushSettingsStatusTarget && !this.hasPushSettingsStateLabelTarget) return

    const state = this.pushSettingsState()
    const readiness = this.pushReadinessState(state)

    this.pushSettingsStatusTargets.forEach((element) => {
      element.textContent = state.message
    })

    this.pushSettingsToggleTargets.forEach((toggle) => {
      toggle.hidden = state.hidden
      toggle.disabled = state.disabled
      toggle.setAttribute("aria-checked", state.checked ? "true" : "false")
      toggle.setAttribute("aria-busy", state.pending ? "true" : "false")
      toggle.classList.toggle("is-active", state.checked)
      toggle.classList.toggle("is-pending", state.pending)
    })

    this.pushSettingsStateLabelTargets.forEach((label) => {
      label.textContent = state.label
      label.classList.toggle("is-active", readiness.overallTone === "ok")
      label.classList.toggle("is-pending", state.pending)
    })

    this.pushSettingsReadinessBadgeTargets.forEach((badge) => {
      badge.hidden = state.hidden
      badge.textContent = readiness.overallLabel
      this.applyPillTone(badge, readiness.overallTone)
    })

    this.pushSettingsTestButtonTargets.forEach((button) => {
      button.hidden = state.hidden
      button.disabled = state.disabled || !state.checked || state.pending || this.pushTestPending
      button.textContent = this.pushTestPending ? "Sending…" : (button.dataset.defaultLabel || "Send test push")
    })

    this.pushSettingsFeedbackTargets.forEach((element) => {
      element.hidden = state.hidden
      element.dataset.state = this.pushSettingsFeedbackTone
    })

    this.pushReadinessCardTargets.forEach((card) => {
      card.hidden = state.hidden
    })
    this.syncPushReadinessCardState()

    this.updateReadinessItem(
      this.pushReadinessPermissionPillTargets,
      this.pushReadinessPermissionDetailTargets,
      readiness.permission
    )
    this.updateReadinessItem(
      this.pushReadinessSubscriptionPillTargets,
      this.pushReadinessSubscriptionDetailTargets,
      readiness.subscription
    )
    this.updateReadinessItem(
      this.pushReadinessDeliveryPillTargets,
      this.pushReadinessDeliveryDetailTargets,
      readiness.delivery
    )
    this.updateReadinessItem(
      this.pushReadinessBannerPillTargets,
      this.pushReadinessBannerDetailTargets,
      readiness.banner
    )

    this.pushBannerActionsTargets.forEach((actions) => {
      actions.hidden = state.hidden || !readiness.showBannerPrompt
    })
    this.pushBannerSeenButtonTargets.forEach((button) => {
      button.disabled = state.hidden || !readiness.showBannerPrompt
    })
    this.pushBannerMissedButtonTargets.forEach((button) => {
      button.disabled = state.hidden || !readiness.showBannerPrompt
    })
  }

  syncOnlineOnlyControls(offline) {
    this.onlineOnlyForms().forEach((form) => {
      this.onlineOnlySubmitControls(form).forEach((control) => {
        if (offline) {
          if (control.disabled) return

          control.dataset.pwaDisabledByOffline = "true"
          control.disabled = true
        } else if (control.dataset.pwaDisabledByOffline === "true") {
          control.disabled = false
          delete control.dataset.pwaDisabledByOffline
        }
      })
    })

    document.querySelectorAll("a[data-turbo-method]").forEach((link) => {
      if (!(link instanceof HTMLElement)) return

      link.classList.toggle("is-pwa-online-only", offline)
      link.setAttribute("aria-disabled", offline ? "true" : "false")
    })
  }

  onlineOnlyForms() {
    return Array.from(document.forms).filter((form) => this.onlineOnlyForm(form))
  }

  onlineOnlyForm(form) {
    return form instanceof HTMLFormElement && form.method.toLowerCase() !== "get"
  }

  onlineOnlySubmitControls(form) {
    return Array.from(
      form.querySelectorAll("button[type='submit'], input[type='submit'], button:not([type])")
    )
  }

  shouldShowInstallPrompt() {
    if (!this.hasInstallPromptTarget) return false
    if (!this.deferredPrompt) return false
    if (!window.navigator.onLine) return false
    if (!this.mobileViewport()) return false
    if (this.standaloneMode()) return false
    if (this.dismissedRecently(INSTALL_DISMISS_KEY)) return false

    return true
  }

  shouldShowIosPrompt() {
    if (!this.hasIosPromptTarget) return false
    if (!this.iosDevice()) return false
    if (!this.mobileViewport()) return false
    if (this.standaloneMode()) return false
    if (this.dismissedRecently(IOS_DISMISS_KEY)) return false
    if (this.deferredPrompt) return false

    return true
  }

  shouldShowPushPrompt() {
    if (!this.hasPushPromptTarget) return false
    if (!this.authenticatedValue) return false
    if (!window.navigator.onLine) return false
    if (!this.pushSupported()) return false
    if (this.pushPermissionState() !== "default") return false
    if (this.dismissedRecently(PUSH_DISMISS_KEY)) return false
    if (this.iosDevice() && !this.standaloneMode()) return false
    if (!this.mobileViewport() && !this.standaloneMode()) return false

    return true
  }

  pushSettingsState() {
    if (!this.authenticatedValue) {
      return {
        hidden: true,
        disabled: true,
        checked: false,
        pending: false,
        label: "Off",
        message: "Sign in to manage push notifications on this device."
      }
    }

    if (!this.webPushPublicKeyValue.length) {
      return {
        hidden: false,
        disabled: true,
        checked: false,
        pending: false,
        label: "Unavailable",
        message: "Push notifications are not configured on this server yet."
      }
    }

    if (this.iosDevice() && !this.standaloneMode()) {
      return {
        hidden: false,
        disabled: true,
        checked: false,
        pending: false,
        label: "Off",
        message: "On iPhone, open Notae from the Home Screen app to enable notifications."
      }
    }

    if (!("Notification" in window) || !("serviceWorker" in navigator) || !("PushManager" in window)) {
      return {
        hidden: false,
        disabled: true,
        checked: false,
        pending: false,
        label: "Unsupported",
        message: "Push notifications are not available on this device/browser yet."
      }
    }

    if (!window.navigator.onLine) {
      return {
        hidden: false,
        disabled: true,
        checked: this.devicePushSubscribed,
        pending: false,
        label: this.devicePushSubscribed ? "On" : "Off",
        message: "Reconnect to enable push notifications on this device."
      }
    }

    const permission = this.pushPermissionState()

    if (this.pushUiPending) {
      return {
        hidden: false,
        disabled: true,
        checked: this.devicePushSubscribed,
        pending: true,
        label: "Working…",
        message: this.devicePushSubscribed ? "Updating this device subscription…" : "Enabling push notifications on this device…"
      }
    }

    if (permission === "granted") {
      const ready = this.pushBannerConfirmed()
      return {
        hidden: false,
        disabled: false,
        checked: this.devicePushSubscribed,
        pending: false,
        label: this.devicePushSubscribed ? (ready ? "Ready" : "Needs review") : "Off",
        message: this.devicePushSubscribed
          ? (ready
            ? "Push notifications are ready on this device."
            : "Push is enabled, but banner visibility still needs verification on this device.")
          : "Notifications are allowed, but this device is not currently subscribed."
      }
    }

    if (permission === "denied") {
      return {
        hidden: false,
        disabled: true,
        checked: false,
        pending: false,
        label: "Blocked",
        message: this.iosDevice()
          ? "Notifications are blocked for Notae on this iPhone. Re-enable them in iPhone notification/site settings, or clear website data and add the app again."
          : "Notifications are blocked for this browser. Re-enable them in browser site settings."
      }
    }

    return {
      hidden: false,
      disabled: false,
      checked: false,
      pending: false,
      label: "Off",
      message: "Enable push notifications for reminders, mentions, approvals, and workflow failures on this device."
    }
  }

  pushReadinessState(state) {
    const permission = this.pushPermissionState()
    const permissionReady = permission === "granted"
    const subscribed = this.devicePushSubscribed
    const delivered = this.pushTestDelivered()
    const bannerConfirmed = this.pushBannerConfirmed()
    const bannerMissed = this.pushBannerMissed()

    const permissionState = permission === "denied"
      ? {
          label: "Blocked",
          tone: "error",
          detail: this.iosDevice()
            ? "iPhone notifications are blocked for this Home Screen app."
            : "Browser notifications are blocked for this site."
        }
      : permissionReady
        ? {
            label: "Allowed",
            tone: "ok",
            detail: "The browser has granted notification permission to Notae."
          }
        : {
            label: "Pending",
            tone: "warn",
            detail: "The browser has not granted notification permission yet."
          }

    const subscriptionState = subscribed
      ? {
          label: "Connected",
          tone: "ok",
          detail: "This browser has an active push subscription for Notae."
        }
      : {
          label: "Missing",
          tone: permissionReady ? "error" : "warn",
          detail: permissionReady
            ? "Permission exists, but this browser is not currently subscribed."
            : "Subscription cannot be created until permission is granted."
        }

    const deliveryState = delivered
      ? {
          label: "Delivered",
          tone: "ok",
          detail: "A test push was delivered to this browser recently."
        }
      : {
          label: "Unverified",
          tone: subscribed ? "warn" : "warn",
          detail: "Run a test push to verify server-to-device delivery for this browser."
        }

    let bannerState
    if (bannerConfirmed) {
      bannerState = {
        label: "Confirmed",
        tone: "ok",
        detail: "A user on this device confirmed seeing the OS-level banner."
      }
    } else if (bannerMissed) {
      bannerState = {
        label: "Missing",
        tone: "error",
        detail: "The browser received a push, but no device banner was seen. Check browser and OS notification presentation settings."
      }
    } else if (delivered) {
      bannerState = {
        label: "Needs check",
        tone: "warn",
        detail: "The push reached this browser. Confirm whether the OS actually showed a banner."
      }
    } else {
      bannerState = {
        label: "Pending",
        tone: "warn",
        detail: "Banner confirmation starts after a successful test push."
      }
    }

    const overallReady = permissionReady && subscribed && delivered && bannerConfirmed
    const overallBlocked = permission === "denied"
    const overallTone = overallReady ? "ok" : (overallBlocked || bannerMissed ? "error" : "warn")
    const overallLabel = overallReady ? "Ready" : (overallBlocked ? "Blocked" : "Needs review")

    return {
      permission: permissionState,
      subscription: subscriptionState,
      delivery: deliveryState,
      banner: bannerState,
      overallTone,
      overallLabel,
      showBannerPrompt: delivered && !bannerConfirmed
    }
  }

  testPushPathFor(element) {
    const directPath = element?.dataset?.pushTestPath
    if (directPath) return directPath

    return this.pushSettingsTestButtonTargets.find((button) => button?.dataset?.pushTestPath)?.dataset?.pushTestPath || ""
  }

  standaloneMode() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  mobileViewport() {
    return window.matchMedia("(max-width: 960px)").matches
  }

  iosDevice() {
    const userAgent = window.navigator.userAgent || ""
    return /iPad|iPhone|iPod/.test(userAgent)
  }

  dismissedRecently(storageKey) {
    const rawValue = window.localStorage.getItem(storageKey)
    if (!rawValue) return false

    const dismissedAt = Number(rawValue)
    if (!Number.isFinite(dismissedAt)) return false

    return Date.now() - dismissedAt < DISMISS_WINDOW_MS
  }

  rememberDismissal(storageKey) {
    window.localStorage.setItem(storageKey, String(Date.now()))
  }

  pushSupported() {
    return (
      this.webPushPublicKeyValue.length > 0 &&
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      "Notification" in window &&
      (window.isSecureContext || ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname))
    )
  }

  pushPermissionState() {
    if (!("Notification" in window)) return "denied"

    return window.Notification.permission
  }

  toggleTargetVisibility(targetName, hidden) {
    const hasTargetProperty = `has${targetName.charAt(0).toUpperCase()}${targetName.slice(1)}Target`
    if (!this[hasTargetProperty]) return

    this[`${targetName}Target`].hidden = hidden
  }

  showNetworkToast(message) {
    if (!this.hasNetworkToastTarget) return

    this.networkToastTarget.textContent = message
    this.networkToastTarget.hidden = false
    this.clearNetworkToast()
    this.networkToastTimeout = window.setTimeout(() => {
      this.networkToastTarget.hidden = true
      this.networkToastTimeout = null
    }, NETWORK_TOAST_MS)
  }

  clearNetworkToast() {
    if (!this.networkToastTimeout) return

    window.clearTimeout(this.networkToastTimeout)
    this.networkToastTimeout = null
  }

  setPushSettingsFeedback(message, tone = "neutral") {
    if (!this.hasPushSettingsFeedbackTarget) return

    this.pushSettingsFeedbackTone = tone
    this.pushSettingsFeedbackTargets.forEach((element) => {
      element.textContent = message
      element.hidden = false
      element.dataset.state = tone
    })
  }

  async subscribeToPushNotifications() {
    if (!this.pushSupported()) {
      this.showNetworkToast("Push notifications are not available on this device yet.")
      this.refreshPushUi()
      return
    }

    const registration = await navigator.serviceWorker.ready.catch(() => null)
    if (!registration) {
      this.showNetworkToast("Push notifications need the Notae app shell to finish loading.")
      this.refreshPushUi()
      return
    }

    let permission = this.pushPermissionState()
    if (permission === "default") {
      permission = await window.Notification.requestPermission()
    }

    if (permission !== "granted") {
      if (permission !== "default") this.rememberDismissal(PUSH_DISMISS_KEY)
      this.syncPushPrompt()
      this.showNetworkToast("Push notifications were not enabled.")
      this.devicePushSubscribed = false
      this.refreshPushUi()
      return
    }

    let subscription = await registration.pushManager.getSubscription()
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.webPushPublicKeyValue)
      })
    }

    await this.persistPushSubscription(subscription)
    this.devicePushSubscribed = true
    this.resetBannerConfirmation()
    window.localStorage.removeItem(PUSH_DISMISS_KEY)
    this.syncPushPrompt()
    this.showNetworkToast("Push notifications enabled.")
    this.refreshPushUi()
  }

  async syncPushSubscription() {
    try {
      if (!this.authenticatedValue) return
      if (!this.pushSupported()) return
      if (this.pushPermissionState() !== "granted") return

      const registration = await navigator.serviceWorker.ready.catch(() => null)
      if (!registration) return

      const subscription = await registration.pushManager.getSubscription()
      if (!subscription) {
        this.devicePushSubscribed = false
        this.syncPushPrompt()
        this.refreshPushUi()
        return
      }

      await this.persistPushSubscription(subscription)
      this.devicePushSubscribed = true
      this.syncPushPrompt()
      this.refreshPushUi()
    } catch (_error) {
      // Ignore best-effort sync failures and keep the app usable.
    }
  }

  async disablePushNotifications() {
    if (!this.pushSupported()) {
      this.refreshPushUi()
      return
    }

    await this.detachPushSubscription()
    this.devicePushSubscribed = false
    this.clearPushReadinessState()
    this.syncPushPrompt()
    this.showNetworkToast("Push notifications turned off on this device.")
    this.refreshPushUi()
  }

  async persistPushSubscription(subscription) {
    const payload = subscription.toJSON()
    const response = await fetch("/pwa/push-subscription", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        subscription: {
          endpoint: subscription.endpoint,
          expiration_time: payload.expirationTime,
          keys: payload.keys || {}
        }
      })
    })

    if (!response.ok) throw new Error("push_subscription_sync_failed")
  }

  async currentPushSubscription() {
    const registration = await navigator.serviceWorker.ready.catch(() => null)
    return registration?.pushManager?.getSubscription?.()
  }

  async rebuildPushSubscription() {
    const registration = await navigator.serviceWorker.ready.catch(() => null)
    if (!registration) throw new Error("push_subscription_refresh_failed")

    const existingSubscription = await registration.pushManager.getSubscription()
    if (existingSubscription) {
      await existingSubscription.unsubscribe().catch(() => {})
    }

    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.urlBase64ToUint8Array(this.webPushPublicKeyValue)
    })

    await this.persistPushSubscription(subscription)
    this.devicePushSubscribed = true
    this.resetBannerConfirmation()
    this.syncPushPrompt()
    this.refreshPushUi()
    return subscription
  }

  async sendTestPushRequest(path, endpoint) {
    return fetch(path, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ endpoint })
    })
  }

  async detachPushSubscription({ keepBrowserSubscription = false } = {}) {
    if (!this.authenticatedValue) return
    if (!this.pushSupported()) return

    const registration = await navigator.serviceWorker.ready.catch(() => null)
    if (!registration) return

    const subscription = await registration.pushManager.getSubscription()
    if (!subscription) return

    await fetch("/pwa/push-subscription", {
      method: "DELETE",
      credentials: "same-origin",
      keepalive: true,
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ endpoint: subscription.endpoint })
    }).catch(() => {})

    if (!keepBrowserSubscription) {
      await subscription.unsubscribe().catch(() => {})
    }

    this.devicePushSubscribed = false
  }

  confirmPushBannerSeen(event) {
    event.preventDefault()
    this.markPushBannerConfirmed()
    this.setPushSettingsFeedback("Banner confirmed on this device. Push notifications now count as ready here.", "success")
    this.showNetworkToast("Banner confirmed on this device.")
    this.refreshPushUi()
  }

  confirmPushBannerMissed(event) {
    event.preventDefault()
    this.markPushBannerMissed()
    this.setPushSettingsFeedback("No device banner was seen. Check browser and OS notification presentation settings for this device.", "error")
    this.showNetworkToast("No device banner was seen.")
    this.refreshPushUi()
  }

  toggleReadinessCenter(event) {
    const panel = event.currentTarget
    if (!(panel instanceof HTMLDetailsElement)) return

    window.localStorage.setItem(PUSH_READINESS_COLLAPSED_KEY, panel.open ? "0" : "1")
  }

  updateReadinessItem(pills, details, itemState) {
    pills.forEach((pill) => {
      pill.textContent = itemState.label
      this.applyPillTone(pill, itemState.tone)
    })
    details.forEach((detail) => {
      detail.textContent = itemState.detail
    })
  }

  applyPillTone(element, tone) {
    element.classList.remove("is-ok", "is-warn", "is-error")
    if (tone === "ok") element.classList.add("is-ok")
    if (tone === "warn") element.classList.add("is-warn")
    if (tone === "error") element.classList.add("is-error")
  }

  markPushTestAttempted() {
    window.localStorage.setItem(PUSH_TEST_SENT_KEY, String(Date.now()))
    this.clearPushBannerMarkers()
  }

  markPushTestDelivered() {
    window.localStorage.setItem(PUSH_TEST_DELIVERED_KEY, String(Date.now()))
    this.clearPushBannerMarkers()
  }

  markPushBannerConfirmed() {
    window.localStorage.setItem(PUSH_BANNER_CONFIRMED_KEY, String(Date.now()))
    window.localStorage.removeItem(PUSH_BANNER_MISSED_KEY)
  }

  markPushBannerMissed() {
    window.localStorage.setItem(PUSH_BANNER_MISSED_KEY, String(Date.now()))
    window.localStorage.removeItem(PUSH_BANNER_CONFIRMED_KEY)
  }

  syncPushReadinessCardState() {
    this.pushReadinessCardTargets.forEach((card) => {
      if (!(card instanceof HTMLDetailsElement) || card.hidden) return

      card.open = !this.pushReadinessCollapsed()
    })
  }

  pushReadinessCollapsed() {
    return window.localStorage.getItem(PUSH_READINESS_COLLAPSED_KEY) === "1"
  }

  clearPushBannerMarkers() {
    window.localStorage.removeItem(PUSH_BANNER_CONFIRMED_KEY)
    window.localStorage.removeItem(PUSH_BANNER_MISSED_KEY)
  }

  resetBannerConfirmation() {
    this.clearPushBannerMarkers()
  }

  clearPushReadinessState() {
    window.localStorage.removeItem(PUSH_TEST_SENT_KEY)
    window.localStorage.removeItem(PUSH_TEST_DELIVERED_KEY)
    this.clearPushBannerMarkers()
  }

  pushTestDelivered() {
    return window.localStorage.getItem(PUSH_TEST_DELIVERED_KEY)?.length > 0
  }

  pushBannerConfirmed() {
    return window.localStorage.getItem(PUSH_BANNER_CONFIRMED_KEY)?.length > 0
  }

  pushBannerMissed() {
    return window.localStorage.getItem(PUSH_BANNER_MISSED_KEY)?.length > 0
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.getAttribute("content") || ""
  }

  urlBase64ToUint8Array(value) {
    const padding = "=".repeat((4 - (value.length % 4)) % 4)
    const base64 = (value + padding).replace(/-/g, "+").replace(/_/g, "/")
    const decoded = window.atob(base64)
    const output = new Uint8Array(decoded.length)

    for (let index = 0; index < decoded.length; index += 1) {
      output[index] = decoded.charCodeAt(index)
    }

    return output
  }

  async clearPrivateCaches() {
    if (!("serviceWorker" in navigator)) return

    if (navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({ type: "CLEAR_PRIVATE_CACHES" })
    }

    try {
      const registration = await navigator.serviceWorker.ready
      registration.active?.postMessage({ type: "CLEAR_PRIVATE_CACHES" })
    } catch (_error) {
      // Ignore service worker readiness failures.
    }
  }
}
