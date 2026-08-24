# frozen_string_literal: true

class User < ApplicationRecord
  enum :role, { user: "user", manager: "manager", admin: "admin" }

  has_many :orders, dependent: :nullify

  validates :name, presence: true
end
