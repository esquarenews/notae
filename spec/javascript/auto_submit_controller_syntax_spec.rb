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
    expect(source).to include("submitOnEnter")
    expect(source).to include("requestSubmit(submitter)")
    expect(source).to include("autoSubmitPending")
    expect(source).to include("focusOnConnectValue")
    expect(source).to include("focusPrimaryInput")
    expect(source).to include("focusNextCreatedRow")
    expect(source).to include("nextRowFocusRequested")
    expect(source).to include("eventForm(event)")
    expect(source).to include("turbo:submit-start")
    expect(source).to include("this.element.addEventListener(\"turbo:submit-start\", this.handleSubmitStart)")
    expect(source).to include("this.element.addEventListener(\"turbo:submit-end\", this.handleSubmitEnd)")
    expect(source).to include("this.clearSubmitting(form)")
    expect(source).to include("captureViewState")
    expect(source).to include("restoreViewState")
    expect(source).to include("window.sessionStorage")
    expect(source).to include("window.scrollTo")
    expect(source).to include("preventScroll: true")
    expect(source).to include('form.dataset.preserveScroll = "true"')
    expect(source).to include('form.dataset.turboStream = "true"')
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
end
