# frozen_string_literal: true

# The three demo people of the switcher — no passwords anywhere: picking a
# person in the top bar is the whole "login".
return if User.any?

User.create!(name: "Uma User", role: "user")
User.create!(name: "Mark Manager", role: "manager")
User.create!(name: "Ada Admin", role: "admin")
