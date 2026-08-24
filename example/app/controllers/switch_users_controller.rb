# frozen_string_literal: true

# The demo user switcher: no passwords, no authentication — authorization
# without it. Picking a person in the top bar is the whole "login".
class SwitchUsersController < ApplicationController
  def create
    user = User.find(params.require(:user_id))
    session[:user_id] = user.id
    redirect_back fallback_location: products_path,
                  notice: "You are now #{user.name} (#{user.role})."
  end
end
