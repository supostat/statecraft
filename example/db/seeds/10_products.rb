# frozen_string_literal: true

module ProductSeeds
  CATALOG = {
    "Walnut desk" => 79_900,
    "Oak bookshelf" => 45_500,
    "Reading lamp" => 12_900,
    "Wool rug" => 28_000,
    "Ceramic vase" => 6_400,
    "Linen curtains" => 15_700
  }.freeze

  module_function

  def seed_catalog
    CATALOG.each { |name, price_cents| Product.create!(name: name, price_cents: price_cents) }
  end
end

ProductSeeds.seed_catalog
