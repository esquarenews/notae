require "rails_helper"

RSpec.describe "dropdown_property_form_controller syntax" do
  it "parses as valid javascript" do
    controller_path = Rails.root.join("app/javascript/controllers/dropdown_property_form_controller.js")
    source = controller_path.read

    expect(source).to include('static targets = ["typeSelect", "panel", "draftInput", "list", "hiddenInputs"]')
    expect(source).to include('input.name = "db_property[select_options_json][]"')
    expect(source).to include('this.panelTarget.hidden = !show')
  end
end
