require "rails_helper"
require "open3"

RSpec.describe "AutoSubmitController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/auto_submit_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "updates task status classes immediately for select cells" do
    source = Rails.root.join("app/javascript/controllers/auto_submit_controller.js").read

    expect(source).to include("applyTaskStatusVisualState")
    expect(source).to include("notae-db-cell-select-status")
    expect(source).to include("applyTaskStatusSelectClasses")
    expect(source).to include("applyTaskStatusRowClasses")
    expect(source).to include("is-status-not-started")
    expect(source).to include("is-status-done")
    expect(source).to include("requestSubmitOnce")
    expect(source).to include("INPUT_DEBOUNCE_MS = 650")
    expect(source).to include("submitDebounced(event)")
    expect(source).to include("this.debounceTimers = new Map()")
    expect(source).to include("window.setTimeout")
    expect(source).to include("clearDebounceTimers()")
    expect(source).to include("clearDebounceTimerFor(event.target)")
    expect(source).to include("submitDetachedInput")
    expect(source).to include("detachedInputHeaders")
    expect(source).to include("window.Turbo.renderStreamMessage(responseBody)")
    expect(source).to include("window.Turbo.renderStreamMessage(responseBody)\n        this.restoreViewState()")
    expect(source).to include("submitOnEnter")
    expect(source).to include("this.clearDebounceTimerFor(event.target)")
    expect(source).to include("requestSubmit(submitter)")
    expect(source).to include("autoSubmitPending")
    expect(source).to include("focusOnConnectValue")
    expect(source).to include("focusPrimaryInput")
    expect(source).to include("focusNextCreatedRow")
    expect(source).to include("nextRowFocusRequested")
    expect(source).to include("createRowFocusRequested")
    expect(source).to include("isCreateNextRowSubmitter(submitter)")
    expect(source).to include('form.dataset.preserveScroll = this.isCreateNextRowSubmitter(submitter) ? "false" : "true"')
    expect(source).to include('submitter.name === "db_row[create_next_row]"')
    expect(source).to include('submitter.value === "1"')
    expect(source).to include("window.sessionStorage.removeItem(this.constructor.VIEW_STATE_KEY)")
    expect(source).to include("isCreateRowForm(form)")
    expect(source).to include("notae-db-new-row-trigger-form")
    expect(source).to include("notae-db-row-hover-control-form")
    expect(source).to include("eventForm(event)")
    expect(source).to include("turbo:submit-start")
    expect(source).to include("this.element.addEventListener(\"turbo:submit-start\", this.handleSubmitStart)")
    expect(source).to include("this.element.addEventListener(\"turbo:submit-end\", this.handleSubmitEnd)")
    expect(source).to include("this.clearSubmitting(form)")
    expect(source).to include("captureViewState")
    expect(source).to include("restoreViewState")
    expect(source).to include("restoreSelection(target, payload)")
    expect(source).to include("supportsSelectionRange(target)")
    expect(source).to include("selectionStart")
    expect(source).to include("selectionEnd")
    expect(source).to include("setSelectionRange")
    expect(source).to include("if (payload?.preservesSelection) return")
    expect(source).to include("window.sessionStorage")
    expect(source).to include("window.scrollTo")
    expect(source).to include("preventScroll: true")
    expect(source).to include('form.dataset.turboStream = "true"')
  end

  it "focuses a newly inserted row once without repeated viewport corrections" do
    source = Rails.root.join("app/javascript/controllers/auto_submit_controller.js").read
    focus_method = source[/  focusNextCreatedRow\(attempt = 0\) \{.*?\n  \}/m]
    enter_method = source[/  submitOnEnter\(event\) \{.*?\n  \}/m]

    expect(focus_method).to include("if (attempt < 20)")
    expect(focus_method.scan("this.focusNextCreatedRow(attempt + 1)").size).to eq(1)
    expect(focus_method).to include("input.focus({ preventScroll: true })")
    expect(enter_method).not_to include("this.focusNextCreatedRow()")
  end

  it "restores the next clicked cell instead of stealing focus back to the submitted cell" do
    source = Rails.root.join("app/javascript/controllers/auto_submit_controller.js").read

    expect(source).to include("installDocumentPointerListener")
    expect(source).to include("removeDocumentPointerListener")
    expect(source).to include("activeControllerCount")
    expect(source).to include("documentPointerDownHandler")
    expect(source).to include("document.addEventListener(\"pointerdown\", this.documentPointerDownHandler, true)")
    expect(source).to include("document.removeEventListener(\"pointerdown\", this.documentPointerDownHandler, true)")
    expect(source).to include("capturePendingFocusTarget(event)")
    expect(source).to include("pendingFocusSelector")
    expect(source).to include("pendingFocusCapturedAt")
    expect(source).to include("this.constructor.pendingFocusSelector")
    expect(source).to include("this.constructor.pendingFocusCapturedAt")
    expect(source).to include("hasPendingConnectFocusTarget")
    expect(source).to include('form[data-auto-submit-focus-on-connect-value="true"]')
    expect(source).to include("preferredFocusSelector(payload)")
    expect(source).to include("payload?.pendingFocusSelector && pendingCapturedAt >= submittedAt")
    expect(source).to include("target.closest(\"input, textarea, select, [contenteditable='true']\")")
    expect(source).to include("this.clearPendingFocusTarget()")
  end

  it "sets timesheet clock cells to the local current datetime" do
    source = Rails.root.join("app/javascript/controllers/auto_submit_controller.js").read

    expect(source).to include("setNow(event)")
    expect(source).to include('closest(".notae-timesheet-clock-cell")')
    expect(source).to include("input[type='datetime-local']")
    expect(source).to include("input.value = this.localDateTimeValue(new Date())")
    expect(source).to include("this.submit({ target: input })")
    expect(source).to include("dispatchTimesheetClockState(target)")
    expect(source).to include("notae:timesheet-timer-started")
    expect(source).to include("notae:timesheet-timer-stopped")
    expect(source).to include("target.dataset.timesheetClockRole")
    expect(source).to include("stoppedAt")
    expect(source).to include("elapsedLabel")
    expect(source).to include("timesheetElapsedLabel(row)")
    expect(source).to include("timesheetStartInput(row)")
    expect(source).to include("timesheetStopInput(row)")
    expect(source).to include("ensureLiveTimesheetTotal(row, target.value)")
    expect(source).to include("removeLiveTimesheetTotal(row)")
    expect(source).to include("notae-timesheet-live-count")
    expect(source).to include("timesheetTotalInput(row)")
    expect(source).to include("localDateTimeValue(date)")
    expect(source).to include('pad(date.getMonth() + 1)')
    expect(source).to include('`T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`')
  end
end
