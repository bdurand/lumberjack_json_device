# frozen_string_literal: true

require "stringio"
require "tempfile"

require_relative "../lib/lumberjack_json_device"

Lumberjack.deprecation_mode = :raise
Lumberjack.raise_logger_errors = true

RSpec.configure do |config|
  config.warnings = true
  config.disable_monkey_patching!
  config.default_formatter = "doc" if config.files_to_run.one?
  config.order = :random
  Kernel.srand config.seed
end
