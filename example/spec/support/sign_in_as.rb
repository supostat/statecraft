# frozen_string_literal: true

# The honest no-JS path through the top-bar switcher — exactly what a
# JS-less visitor does, and therefore what rack_test can do.
module SignInAs
  def sign_in_as(name)
    visit products_path
    within(".user-switcher") do
      select name, from: "user_id"
      click_button "Switch"
    end
  end
end

RSpec.configure do |config|
  config.include SignInAs, type: :system
end
