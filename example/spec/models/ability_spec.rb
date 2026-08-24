# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ability do
  def order_owned_by(user)
    OrderSeeds.place_order(number: "SPEC-ABL-#{user.role}", customer: user.name,
                           items: { "Reading lamp" => 1 }, user: user)
  end

  let(:uma) { User.find_by!(role: "user") }
  let(:mark) { User.find_by!(role: "manager") }
  let(:ada) { User.find_by!(role: "admin") }

  describe "a customer" do
    it "acts on their own orders only, in storefront verbs" do
      ability = described_class.new(uma)
      own = order_owned_by(uma)
      foreign = order_owned_by(mark)

      expect(ability.can?(:pay, own)).to be(true)
      expect(ability.can?(:cancel, own)).to be(true)
      expect(ability.can?(:pay, foreign)).to be(false)
      expect(ability.can?(:cancel, foreign)).to be(false)
      expect(ability.can?(:access, :admin_zone)).to be(false)
      expect(ability.can?(:capture, Payment)).to be(false)
    end
  end

  describe "a manager" do
    it "works the desks but never pays an order directly" do
      ability = described_class.new(mark)

      expect(ability.can?(:access, :admin_zone)).to be(true)
      expect(ability.can?(:capture, Payment)).to be(true)
      expect(ability.can?(:save_and_capture, Payment)).to be(true)
      expect(ability.can?(:pack, Shipment)).to be(true)
      expect(ability.can?(:deliver, Shipment)).to be(true)
      expect(ability.can?(:refund, order_owned_by(uma))).to be(true)
      expect(ability.can?(:create_shipment, Order)).to be(true)

      # As a customer Mark still pays his OWN order; the desk gives him no
      # power to pay anyone else's — that path goes through ConfirmPayment.
      expect(ability.can?(:pay, order_owned_by(mark))).to be(true)
      expect(ability.can?(:pay, order_owned_by(uma))).to be(false)
      expect(ability.can?(:admin_override, Order)).to be(false)
      expect(ability.can?(:bypass_cancel, Order)).to be(false)
    end
  end

  describe "an admin" do
    it "owns the whole event surface, privileged paths included" do
      ability = described_class.new(ada)

      expect(ability.can?(:access, :admin_zone)).to be(true)
      expect(ability.can?(:pay, order_owned_by(uma))).to be(true)
      expect(ability.can?(:admin_override, Order)).to be(true)
      expect(ability.can?(:bypass_cancel, Order)).to be(true)
      expect(ability.can?(:capture, Payment)).to be(true)
    end
  end
end
