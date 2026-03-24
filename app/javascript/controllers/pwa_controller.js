import { Controller } from "@hotwired/stimulus"

const INSTALL_DISMISS_KEY = "notae-pwa-install-dismissed-at"
const IOS_DISMISS_KEY = "notae-pwa-ios-dismissed-at"
const PUSH_DISMISS_KEY = "notae-pwa-push-dismissed-at"
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
    "pushSettingsStatus"
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
    this.beforeInstallPromptHandler = (event) => this.handleBeforeInstallPrompt(event)
    this.appInstalledHandler = () => this.handleAppInstalled()
    this.onlineHandler = () => this.refreshNetworkState()
    this.offlineHandler = () => this.refreshNetworkState()
    this.submitHandler = (event) => this.handleDocumentSubmit(event)
    this.clickHandler = (event) => this.handleDocumentClick(event)
    this.turboLoadHandler = () => this.refreshNetworkState()

    window.addEventListener("beforeinstallprompt", this.beforeInstallPromptHandler)
    window.addEventListener("appinstalled", this.appInstalledHandler)
    window.addEventListener("online", this.onlineHandler)
    window.addEventListener("offline", this.offlineHandler)
    document.addEventListener("submit", this.submitHandler, true)
    document.addEventListener("click", this.clickHandler, true)
    document.addEventListener("turbo:load", this.turboLoadHandler)

    if (!this.authenticatedValue) this.clearPrivateCaches()

    this.refreshNetworkState()
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
      label.classList.toggle("is-active", state.checked)
      label.classList.toggle("is-pending", state.pending)
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
      return {
        hidden: false,
        disabled: false,
        checked: this.devicePushSubscribed,
        pending: false,
        label: this.devicePushSubscribed ? "On" : "Off",
        message: this.devicePushSubscribed ? "Push notifications are enabled on this device." : "Notifications are allowed, but this device is not currently subscribed."
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
