# frozen_string_literal: true
require "liquid/spec/cli/adapter_dsl"
require "liquid/spec/json_rpc/adapter"
require "liquid" # Required by the harness's host-side fixture types; never used to render.
require "shellwords"

LiquidSpec.configure do |config|
  config.suites = [:basics, :liquid_ruby, :partials, :parser_errors]
  config.error_modes = [:strict2]
  config.render_error_modes = [:raise]
  # Host-language objects, Shopify storefront extensions and reference-engine
  # score accounting are separate capabilities, not hidden standard-tag skips.
  config.missing_features = [
    :drops, :ruby_drops, :ruby_types, :drop_class_output, :binary_data,
    :template_factory, :shopify_tags, :shopify_objects, :shopify_filters,
    :shopify_includes, :shopify_blank, :shopify_error_handling,
    :shopify_error_format, :shopify_string_access, :shopify_resource_limits,
    :range_resource_limits, :strict2_blank_body_errors, :randomness,
  ]
end

LiquidSpec.setup do |ctx|
  ctx[:adapter] = Liquid::Spec::JsonRpc::Adapter.new(Shellwords.escape(ENV.fetch("LIQUID_SWIFT_ADAPTER")), timeout: 5)
  ctx[:adapter].start
  at_exit { ctx[:adapter].shutdown }
end
LiquidSpec.compile do |ctx, source, options|
  ctx[:template_id] = ctx[:adapter].compile(source, options)
end
LiquidSpec.render do |ctx, assigns, options|
  ctx[:adapter].render(ctx[:template_id], assigns, options)
end
