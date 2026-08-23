# frozen_string_literal: true

module Statecraft
  # Normalizes transition metadata to exactly what will survive the jsonb
  # round-trip, then deep-freezes it: what the guards checked is what the log
  # stored. Symbols become strings (keys and values), times become ISO-8601
  # strings, and anything that JSON cannot represent fails instantly at the
  # pipeline entrance instead of inside the transaction.
  module Metadata
    def self.normalize(raw_metadata)
      deep_freeze(round_trip(raw_metadata))
    end

    def self.round_trip(value)
      case value
      when Hash
        value.to_h { |key, nested| [round_trip_key(key), round_trip(nested)] }
      when Array
        value.map { |element| round_trip(element) }
      when String then value.dup
      when Symbol then value.to_s
      when Integer, Float, true, false, nil then value
      when Time, Date, DateTime then value.iso8601
      else
        raise ArgumentError,
              "metadata value #{value.inspect} (#{value.class}) is not JSON-serializable; " \
              "metadata must round-trip through jsonb"
      end
    end

    def self.round_trip_key(key)
      case key
      when String then key.dup
      when Symbol, Integer then key.to_s
      else
        raise ArgumentError,
              "metadata key #{key.inspect} (#{key.class}) is not a JSON object key"
      end
    end

    def self.deep_freeze(value)
      case value
      when Hash
        value.each { |key, nested| key.freeze && deep_freeze(nested) }
      when Array
        value.each { |element| deep_freeze(element) }
      end
      value.freeze
    end
  end
end
