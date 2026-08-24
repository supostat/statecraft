# frozen_string_literal: true

# The single truth about permissions: roles map straight onto the machines'
# events — the machine says WHAT is possible from a state, this class says
# WHO may do it, and a button renders only in the intersection.
class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new(role: "user")

    # A customer acts on their own orders in storefront words.
    can %i[pay cancel], Order, user_id: user.id

    return unless user.manager? || user.admin?

    can :access, :admin_zone
    # A manager never pays an order directly: an order becomes paid only
    # through confirming its payment.
    can %i[refund cancel preview create_shipment], Order
    can %i[capture save_and_capture], Payment
    can %i[pack ship deliver], Shipment

    return unless user.admin?

    can %i[pay admin_override bypass_cancel], Order
  end
end
