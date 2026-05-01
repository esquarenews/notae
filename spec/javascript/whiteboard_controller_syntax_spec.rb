require "rails_helper"

RSpec.describe "whiteboard controller syntax" do
  it "keeps pointer drawing, fullscreen collapse and autosave wired" do
    source = Rails.root.join("app/javascript/controllers/whiteboard_controller.js").read

    expect(source).to include('static targets = [ "canvas", "status", "toolButton", "colorButton", "openButton", "collapseButton" ]')
    expect(source).to include('this.canvasTarget.addEventListener("pointerdown", this.pointerDownHandler)')
    expect(source).to include('this.canvasTarget.addEventListener("pointermove", this.pointerMoveHandler)')
    expect(source).to include('this.canvasTarget.addEventListener("pointerup", this.pointerUpHandler)')
    expect(source).to include('this.element.classList.add("is-fullscreen")')
    expect(source).to include('this.element.classList.remove("is-fullscreen")')
    expect(source).to include('JSON.stringify({ block: { content_json: content } })')
    expect(source).to include('delete content.whiteboard_autofocus')
    expect(source).to include('this.strokeTouchesPoint(stroke, point, radius)')
  end
end
