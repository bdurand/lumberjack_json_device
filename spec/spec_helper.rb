# frozen_string_literal: true

require "stringio"
require "tempfile"

require_relative "../lib/lumberjack_json_device"

RSpec.configure do |config|
  config.warnings = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end

def silence_deprecations
  save_warning = ENV["LUMBERJACK_DEPRECATION_WARNINGS"]
  save_verbose = $VERBOSE
  begin
    ENV["LUMBERJACK_DEPRECATION_WARNINGS"] = "false"
    $VERBOSE = false
    begin
      yield
    ensure
      ENV["LUMBERJACK_DEPRECATION_WARNINGS"] = save_warning
      $VERBOSE = save_verbose
    end
  end
end
