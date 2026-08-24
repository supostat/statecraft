# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_24_130001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "operation_entries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_name"
    t.string "from_state"
    t.string "outcome", null: false
    t.string "reason"
    t.string "record_class", null: false
    t.string "record_id", null: false
    t.string "to_state"
  end

  create_table "order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_cents", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "order_transitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event"
    t.string "from_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "order_id", null: false
    t.string "to_state", null: false
    t.index ["order_id", "id"], name: "index_order_transitions_on_order_id_and_id"
  end

  create_table "orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "customer_name"
    t.boolean "express", default: false, null: false
    t.string "number", null: false
    t.string "state", default: "pending", null: false
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["state"], name: "index_orders_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'paid'::character varying::text, 'refunded'::character varying::text, 'cancelled'::character varying::text])", name: "orders_state_check"
  end

  create_table "payment_transitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event"
    t.string "from_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "payment_id", null: false
    t.string "to_state", null: false
    t.index ["payment_id", "id"], name: "index_payment_transitions_on_payment_id_and_id"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "amount_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "number", null: false
    t.bigint "order_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_payments_on_order_id", unique: true
    t.index ["state"], name: "index_payments_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'captured'::character varying::text])", name: "payments_state_check"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "price_cents", null: false
    t.datetime "updated_at", null: false
  end

  create_table "shipment_transitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event"
    t.string "from_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "shipment_id", null: false
    t.string "to_state", null: false
    t.index ["shipment_id", "id"], name: "index_shipment_transitions_on_shipment_id_and_id"
  end

  create_table "shipments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "number", null: false
    t.bigint "order_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_shipments_on_order_id", unique: true
    t.index ["state"], name: "index_shipments_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'packed'::character varying::text, 'shipped'::character varying::text, 'delivered'::character varying::text])", name: "shipments_state_check"
  end

  create_table "shop_order_transitions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event"
    t.string "from_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "order_id", null: false
    t.string "to_state", null: false
    t.index ["order_id", "id"], name: "index_shop_order_transitions_on_order_id_and_id"
  end

  create_table "shop_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "state", default: "pending", null: false
    t.datetime "state_changed_at"
    t.datetime "updated_at", null: false
    t.index ["state"], name: "index_shop_orders_on_state"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying::text, 'paid'::character varying::text])", name: "shop_orders_state_check"
  end

  add_foreign_key "order_items", "orders", on_delete: :cascade
  add_foreign_key "order_items", "products"
  add_foreign_key "order_transitions", "orders", on_delete: :cascade
  add_foreign_key "payment_transitions", "payments", on_delete: :cascade
  add_foreign_key "payments", "orders", on_delete: :cascade
  add_foreign_key "shipment_transitions", "shipments", on_delete: :cascade
  add_foreign_key "shipments", "orders", on_delete: :cascade
  add_foreign_key "shop_order_transitions", "shop_orders", column: "order_id", on_delete: :cascade
end
