#!/usr/bin/env ruby
# frozen_string_literal: true

# The two-way catalog lock. CATALOG.md is the single source of truth for
# protocol coverage; this script keeps it honest in both directions:
#   * an example-genre item without a `# catalog: NN-slug` marker is red;
#   * a marker pointing at a missing or misnamed item is red;
#   * a line the grammar cannot parse is red — freeform prose cannot creep in.
# Suite-genre items are proven by the gem's own acceptance spec and need no
# example marker. The human-readable table is GENERATED here (--table); a
# hand-written copy of the mapping is forbidden by design.

EXAMPLE_DIR = File.expand_path("..", __dir__)
CATALOG_PATH = File.join(EXAMPLE_DIR, "CATALOG.md")

ITEM = /\A- (\d+)\. ([a-z0-9-]+) — (.+) · (suite|scene|spec)\z/
MARKER = /^\s*(?:#|<%#)\s*catalog: (\d+)-([a-z0-9-]+)/

errors = []
items = {}

File.readlines(CATALOG_PATH, chomp: true).each_with_index do |line, index|
  next if line.empty? || line.start_with?("#")

  match = ITEM.match(line)
  if match.nil?
    errors << "CATALOG.md:#{index + 1} does not parse: #{line.inspect}"
    next
  end

  number = Integer(match[1], 10)
  errors << "CATALOG.md:#{index + 1} duplicates item #{number}" if items.key?(number)
  items[number] = { slug: match[2], genre: match[4], markers: [] }
end

items.keys.each_cons(2) do |left, right|
  errors << "CATALOG.md: item #{right} breaks ascending numbering after #{left}" if right <= left
end

Dir.glob(File.join(EXAMPLE_DIR, "spec", "**", "*.rb")).sort.each do |path|
  File.readlines(path, chomp: true).each_with_index do |line, index|
    line.scan(MARKER) do |number_text, slug|
      number = Integer(number_text, 10)
      relative = path.delete_prefix("#{EXAMPLE_DIR}/")
      item = items[number]
      if item.nil?
        errors << "#{relative}:#{index + 1} marks unknown item #{number}-#{slug}"
      elsif item[:slug] != slug
        errors << "#{relative}:#{index + 1} marks #{number} as #{slug.inspect}, catalog says #{item[:slug].inspect}"
      else
        item[:markers] << relative
      end
    end
  end
end

items.each do |number, item|
  next if item[:genre] == "suite"

  errors << "item #{number}-#{item[:slug]} (#{item[:genre]}) has no marker in the example suite" if item[:markers].empty?
end

if ARGV.include?("--table")
  puts format("%-4s %-34s %-6s %s", "NN", "slug", "genre", "proof")
  items.each do |number, item|
    proofs = item[:genre] == "suite" ? "spec/wire/acceptance_spec.rb (gem)" : item[:markers].uniq.join(", ")
    puts format("%-4d %-34s %-6s %s", number, item[:slug], item[:genre], proofs)
  end
end

if errors.any?
  errors.each { |error| warn "catalog: #{error}" }
  exit 1
end

puts "catalog: #{items.size} items, two-way lock green"
