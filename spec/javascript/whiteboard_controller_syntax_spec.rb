require "rails_helper"

RSpec.describe "whiteboard controller syntax" do
  it "keeps pointer drawing, fullscreen collapse and autosave wired" do
    source = Rails.root.join("app/javascript/controllers/whiteboard_controller.js").read

    expect(source).to include('static targets = [ "canvas", "status", "toolButton", "colorButton", "colorInput", "diameterInput", "diameterValue", "openButton", "collapseButton" ]')
    expect(source).to include('this.canvasTarget.addEventListener("pointerdown", this.pointerDownHandler)')
    expect(source).to include('this.canvasTarget.addEventListener("pointermove", this.pointerMoveHandler)')
    expect(source).to include('this.canvasTarget.addEventListener("pointerup", this.pointerUpHandler)')
    expect(source).to include("const coalescedEvents = event.getCoalescedEvents?.()")
    expect(source).to include("const pointerEvents = coalescedEvents?.length ? coalescedEvents : [ event ]")
    expect(source).to include("this.drawStrokeSegment(this.activeStroke, previous, point)")
    expect(source).to include("applyStrokeStyle(context, stroke)")
    expect(source).to include("context.shadowBlur = Math.max")
    expect(source).to include('this.element.classList.add("is-fullscreen")')
    expect(source).to include('document.documentElement.classList.add("notae-whiteboard-open")')
    expect(source).to include('this.element.classList.remove("is-fullscreen")')
    expect(source).to include('selectCustomColor(event)')
    expect(source).to include("selectDiameter(event)")
    expect(source).to include("MIN_DIAMETER")
    expect(source).to include("MAX_DIAMETER")
    expect(source).to include('this.colorInputTarget.value = this.normalizedColor(this.color)')
    expect(source).to include('this.diameterValueTarget.textContent = `${this.diameter}px`')
    expect(source).to include('if (!this.fullscreenActive())')
    expect(source).to include('JSON.stringify({ block: { content_json: content } })')
    expect(source).to include('delete content.whiteboard_autofocus')
    expect(source).to include('this.strokeTouchesPoint(stroke, point, radius)')
  end
end
