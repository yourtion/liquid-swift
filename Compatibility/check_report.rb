# frozen_string_literal: true
require "json"
require "digest"

report = JSON.parse(File.read(ARGV.fetch(0)))
summary = JSON.parse(File.read(File.join(__dir__, "summary.json")))
revision = File.read(File.join(__dir__, "upstream-revision.txt")).strip
source = File.read(File.join(__dir__, "Gemfile.lock")).split("\n\n").find { |block| block.include?("remote: https://github.com/Shopify/liquid-spec.git") }
locked_revision = source&.match(/^  revision: ([0-9a-f]{40})$/)&.captures&.first
raise "Upstream revision metadata/lock mismatch" unless revision == locked_revision && summary.fetch("revision") == revision
raise "Declared capability profile changed" unless report.fetch("missing_features").sort == summary.fetch("missing_features").sort
passed = report.fetch("passed").map { |entry| entry.fetch("name") }.sort
all_names = %w[passed failures known_failures].flat_map { |key| report.fetch(key).map { |entry| entry.fetch("name") } }
raise "Official spec inventory changed: #{all_names.size}, expected #{summary.fetch("tracked_specs")}" unless all_names.size == summary.fetch("tracked_specs")
digest = Digest::SHA256.hexdigest(passed.join("\n") + "\n")
raise "Passing spec inventory changed. Inspect regressions or remove newly fixed known failures." unless digest == summary.fetch("passing_ids_sha256")
puts "Compatibility inventory verified: #{passed.size} passing, #{report.fetch("known_failures").size} known failures."
