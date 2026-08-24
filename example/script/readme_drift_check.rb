#!/usr/bin/env ruby
# frozen_string_literal: true

# The README drift lock. Fenced blocks in the gem README that pretend to be
# executable are anchored to regions of the example app
# (`# readme: <label>` … `# /readme`, ERB comments included) and compared
# VERBATIM — the code is right, the README catches up by hand; this script
# never edits anything. Every ```ruby block in the README must be marked:
# either `<!-- readme: <label> -->` (anchored) or `<!-- illustrative -->`.
# An unmarked ruby block, a label without a region, a region without a
# block, or a single differing line is red.

EXAMPLE_DIR = File.expand_path("..", __dir__)
GEM_ROOT = File.expand_path("../..", __dir__)
README_PATH = File.join(GEM_ROOT, "README.md")

REGION_START = /(?:#|<%#)\s*readme: ([a-z-]+)/
REGION_END = %r{(?:#|<%#)\s*/readme}

errors = []

regions = {}
Dir.glob(File.join(EXAMPLE_DIR, "{app,config,db}", "**", "*.{rb,erb}")).sort.each do |path|
  relative = path.delete_prefix("#{GEM_ROOT}/")
  current_label = nil
  collected = []
  File.readlines(path, chomp: true).each do |line|
    if (match = REGION_START.match(line))
      current_label = match[1]
      collected = []
    elsif REGION_END.match?(line)
      next if current_label.nil?

      errors << "region #{current_label.inspect} is declared twice" if regions.key?(current_label)
      regions[current_label] = { file: relative, lines: collected }
      current_label = nil
    elsif current_label
      collected << line
    end
  end
  errors << "#{relative}: region #{current_label.inspect} is never closed" if current_label
end

readme_lines = File.readlines(README_PATH, chomp: true)
anchored = {}
open_fence = nil
fence_language = nil
fence_lines = []
fence_marker = nil

readme_lines.each_with_index do |line, index|
  if open_fence.nil? && (match = /\A```(\w*)\z/.match(line))
    open_fence = index + 1
    fence_language = match[1]
    fence_lines = []
    fence_marker = nil
    lookback = readme_lines[[index - 3, 0].max...index].reject(&:empty?)
    lookback.each do |above|
      fence_marker = :illustrative if above.include?("<!-- illustrative -->")
      fence_marker = Regexp.last_match(1) if above =~ /<!-- readme: ([a-z-]+) -->/
    end
  elsif open_fence && line == "```"
    if fence_marker.is_a?(String)
      errors << "README.md:#{open_fence} anchors #{fence_marker.inspect} twice" if anchored.key?(fence_marker)
      anchored[fence_marker] = fence_lines
    elsif fence_marker.nil? && fence_language == "ruby"
      errors << "README.md:#{open_fence} has an unmarked ruby block — mark it " \
                "<!-- readme: <label> --> or <!-- illustrative -->"
    end
    open_fence = nil
  elsif open_fence
    fence_lines << line
  end
end

anchored.each do |label, block_lines|
  region = regions[label]
  if region.nil?
    errors << "README anchors #{label.inspect}, but the example has no such region"
    next
  end

  next if region[:lines] == block_lines

  divergence = region[:lines].zip(block_lines).index { |ours, theirs| ours != theirs } || 0
  errors << "#{label.inspect} drifted from #{region[:file]} at region line #{divergence + 1}: " \
            "code says #{region[:lines][divergence].inspect}, README says #{block_lines[divergence].inspect}"
end

regions.each_key do |label|
  errors << "region #{label.inspect} in the example has no anchored README block" unless anchored.key?(label)
end

if errors.any?
  errors.each { |error| warn "readme-drift: #{error}" }
  exit 1
end

puts "readme-drift: #{anchored.size} anchored blocks verbatim, #{readme_lines.count { |l| l == "```" }} fences scanned"
