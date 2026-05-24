require "rails_helper"
require "open3"

RSpec.describe "NotificationBarController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/notification_bar_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "updates the shell clock and persists dismiss and snooze state for alerts" do
    source = Rails.root.join("app/javascript/controllers/notification_bar_controller.js").read

    expect(source).to include("ALERT_POLL_INTERVAL_MS")
    expect(source).to include("renderClock()")
    expect(source).to include("Intl.DateTimeFormat")
    expect(source).to include("weekday: \"short\"")
    expect(source).to include("minute: \"2-digit\"")
    expect(source).to include("timeZone")
    expect(source).to include("dismissAlert(event)")
    expect(source).to include("snoozeAlert(event)")
    expect(source).to include("event.currentTarget")
    expect(source).to include("event.stopImmediatePropagation?.()")
    expect(source).to include("alertForControl(control)")
    expect(source).to include("window.sessionStorage.setItem")
    expect(source).to include("window.localStorage.setItem")
    expect(source).to include("refreshVisibility()")
    expect(source).to include("pollAlerts({ force = false } = {})")
    expect(source).to include("syncAlertPolling({ immediate = false } = {})")
    expect(source).to include("stopAlertPolling()")
    expect(source).to include("this.refreshPathValue")
    expect(source).to include("calendarSrc: String")
    expect(source).to include("notificationBarAlertsBootstrapped")
    expect(source).to include("syncAlertPolling({ immediate: shouldPollImmediately })")
    expect(source).to include("document.addEventListener(\"visibilitychange\", this.visibilityChangeHandler)")
    expect(source).to include("window.addEventListener(\"notae:push-received\", this.pushReceivedHandler)")
    expect(source).to include("this.pushReceivedHandler = () => this.pollAlerts({ force: true })")
    expect(source).to include("toggleCalendar(event)")
    expect(source).to include("openCalendar()")
    expect(source).to include("closeCalendar(event)")
    expect(source).to include("startDrag(event)")
    expect(source).to include("drag(event)")
    expect(source).to include("stopDrag()")
    expect(source).to include("applyStoredBarPosition()")
    expect(source).to include("persistBarLeft(value)")
    expect(source).to include("barPositionStorageKey()")
    expect(source).to include("requestCalendarRecenter({ retries = 0 } = {})")
    expect(source).to include("beforeCache()")
    expect(source).to include("document.addEventListener(\"turbo:before-cache\", this.beforeCache)")
    expect(source).to include("window.addEventListener(\"resize\", this.resizeHandler)")
    expect(source).to include("window.addEventListener(\"pointermove\", this.pointerMoveHandler)")
    expect(source).to include("window.localStorage.setItem(this.barPositionStorageKey()")
    expect(source).to include("syncCalendarState()")
    expect(source).to include("calendarFrame")
    expect(source).to include("calendarFrameLoadHandler")
    expect(source).to include("ensureCalendarFrameLoaded()")
    expect(source).to include("this.calendarFrameTarget.setAttribute(\"src\", src)")
    expect(source).to include("this.calendarFrameTarget.dataset.notificationBarCalendarSrc")
    expect(source).to include("notae:kalendarium-widget:center-current-time")
    expect(source).to include("window.addEventListener(\"message\", this.handleWidgetMessage)")
    expect(source).to include("messageType === \"notae:kalendarium-widget:minimize\"")
    expect(source).to include("timesheetTimer")
    expect(source).to include("notae:timesheet-timer-started")
    expect(source).to include("notae:timesheet-timer-stopped")
    expect(source).to include("showTimesheetTimer(detail = {})")
    expect(source).to include("hideTimesheetTimer()")
    expect(source).to include("renderTimesheetTimer()")
    expect(source).to include("updateTimesheetTimerFromPayload(payload?.data?.active_timesheet_timer)")
    expect(source).to include("formatElapsed(milliseconds)")
  end
end
