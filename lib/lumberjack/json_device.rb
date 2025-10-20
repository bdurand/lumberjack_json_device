# frozen_string_literal: true

require "lumberjack"
require "json"
require "time"

# Lumberjack is a simple, powerful, and fast logging library for Ruby that
# provides a consistent interface for logging across different output streams.
module Lumberjack
  # This Lumberjack device logs output to another device as JSON formatted text with one document per line.
  # This format (JSONL) is ideal for structured logging pipelines and can be easily consumed by log
  # aggregation services, search engines, and monitoring tools.
  #
  # The device supports flexible field mapping to customize the JSON structure, datetime formatting,
  # post-processing, and pretty printing for development use.
  #
  # @example Basic usage
  #   device = Lumberjack::JsonDevice.new(output: STDOUT)
  #   logger = Lumberjack::Logger.new(device)
  #   logger.info("User logged in", user_id: 123)
  #
  # @example Custom field mapping
  #   device = Lumberjack::JsonDevice.new(
  #     output: STDOUT,
  #     mapping: {
  #       time: "timestamp",
  #       severity: "level",
  #       message: true,
  #       attributes: "*"
  #     }
  #   )
  #
  # The mapping parameter can be used to define the JSON data structure. To define the structure pass in a
  # hash with key indicating the log entry field and the value indicating the JSON document key.
  #
  # The standard entry fields are mapped with the following keys:
  #
  # * :time
  # * :severity
  # * :progname
  # * :pid
  # * :message
  # * :attributes
  #
  # Any additional keys will be pulled from the attributes. If any of the standard keys are missing or have a nil
  # mapping, the entry field will not be included in the JSON output.
  #
  # You can create a nested JSON structure by specifying an array as the JSON key.
  class JsonDevice < Device
    VERSION = File.read(File.join(__dir__, "..", "..", "VERSION")).strip.freeze

    # Default mapping for standard log entry fields to JSON keys.
    DEFAULT_MAPPING = {
      time: true,
      severity: true,
      message: true,
      progname: true,
      pid: true,
      attributes: true
    }.freeze

    # Default ISO 8601 datetime format with microsecond precision and timezone offset.
    DEFAULT_TIME_FORMAT = "%Y-%m-%dT%H:%M:%S.%6N%z"

    # Classes that can be serialized directly to JSON without transformation.
    JSON_NATIVE_CLASSES = [String, NilClass, Numeric, TrueClass, FalseClass].freeze
    private_constant :JSON_NATIVE_CLASSES

    # Valid options that can be passed to the JsonDevice constructor.
    JSON_OPTIONS = [:output, :mapping, :formatter, :datetime_format, :post_processor, :pretty, :utc].freeze
    private_constant :JSON_OPTIONS

    # Register the JsonDevice with the device registry for easier instantiation.
    DeviceRegistry.add(:json, self)

    # @!attribute [rw] formatter
    #   @return [Lumberjack::Formatter] The formatter used to format log entry values before JSON serialization.
    attr_accessor :formatter

    # @!attribute [rw] post_processor
    #   @return [Proc, nil] A callable object that can modify the log entry hash before JSON serialization.
    attr_accessor :post_processor

    # @!attribute [w] pretty
    #   @param value [Boolean] Whether to enable pretty-printed JSON output.
    attr_writer :pretty

    # @!attribute [r] mapping
    #   @return [Hash] The current field mapping configuration.
    attr_reader :mapping

    # Create a new JsonDevice instance.
    #
    # @param options [Hash<Symbol, Object>] The options for the JSON device.
    # @param deprecated_options [Hash<Symbol, Object>] The device options for the JSON device if the output
    #   stream or device is specified in the first argument. This is deprecated behavior for backward
    #   compatibility with version 2.x.
    # @option options [IO, Lumberjack::Device, Symbol, String, Pathname, nil] :output The output stream or
    #   Lumberjack device to write the JSON formatted log entries to. If this is a string or Pathname,
    #   then the output will be written to that file path. The values :stdout and :stderr can be used
    #   to write to STDOUT and STDERR respectively. Defaults to STDOUT.
    # @option options [Hash] :mapping A hash where the key is the log entry field name and the value indicates how
    #   to map the field if it exists. If the value is `true`, the field will be mapped to the same name.
    #   If the value is a String, the field will be mapped to that key name.
    #   If the value is an Array, it will be mapped to a nested structure that follows the array elements.
    #   If the value is a callable object, it will be called with the value and is expected to return
    #   a hash that will be merged into the JSON document.
    #   If the value is `false` or `nil`, the field will not be included in the JSON output.
    #   Special value `"*"` for `:attributes` will flatten all remaining attributes to the root level.
    # @option options [Lumberjack::Formatter] :formatter An optional formatter to use for formatting the log entry data.
    # @option options [String] :datetime_format An optional datetime format string to use for formatting the log timestamp.
    #   Defaults to ISO 8601 format with microsecond precision.
    # @option options [Proc] :post_processor An optional callable object that will be called with the log entry hash
    #   before it is written to the output stream. This can be used to modify the log entry data
    #   before it is serialized to JSON. The callable should return a Hash or the result will be ignored.
    # @option options [Boolean] :pretty If true, the output will be formatted as pretty JSON with indentation and newlines.
    #   The default is false, which writes each log entry as a single line JSON document.
    # @option options [Boolean] :utc If true, all times will be converted to UTC before formatting.
    def initialize(options = {}, deprecated_options = nil)
      unless options.is_a?(Hash)
        Lumberjack::Utils.deprecated(:new, "Passing a stream or device as the first argument is no longer supported and will be removed in version 3.1; specify the output stream in the :output key of the options hash.") do
          options = (deprecated_options || {}).merge(output: options)
        end
      end

      @mutex = Mutex.new

      stream_options = options.dup
      JSON_OPTIONS.each { |key| stream_options.delete(key) }
      @output = output_stream(options[:output], stream_options)

      self.mapping = options.fetch(:mapping, DEFAULT_MAPPING)

      @force_utc = options.fetch(:utc, false)
      @formatter = default_formatter
      self.datetime_format = options.fetch(:datetime_format, DEFAULT_TIME_FORMAT)
      @formatter.include(options[:formatter]) if options[:formatter]

      @post_processor = options[:post_processor]

      @pretty = !!options[:pretty]
    end

    # Write a log entry to the output stream as JSON.
    # Each entry is written as a single line JSON document (JSONL format) unless pretty printing is enabled.
    # Empty log entries (nil or empty message) are ignored.
    #
    # @param entry [Lumberjack::LogEntry] The log entry to write.
    # @return [void]
    def write(entry)
      return if entry.empty?

      data = entry_as_json(entry)
      json = @pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      @output.write("#{json}\n")
    end

    # Get the underlying device from the output stream.
    #
    # @return [Object] The underlying device.
    def dev
      @output.dev
    end

    # Flush the output stream.
    #
    # @return [void]
    def flush
      @output.flush
    end

    # @!attribute [r] datetime_format
    #   @return [String] The current datetime format string.
    attr_reader :datetime_format

    # Set the datetime format for the log timestamp.
    #
    # @param format [String] The datetime format string to use for formatting the log timestamp.
    def datetime_format=(format)
      @datetime_format = format
      fmttr = time_formatter(datetime_format: format, force_utc: @force_utc)
      @formatter.add(Time, fmttr)
      @formatter.add(DateTime, fmttr)
    end

    # Return true if the output is written in a multi-line pretty format. The default is to write each
    # log entry as a single line JSON document.
    #
    # @return [Boolean]
    def pretty?
      !!@pretty
    end

    # Set the mapping for how to map an entry to a JSON object.
    #
    # @param mapping [Hash] A hash where the key is the log entry field name and the value is the JSON key.
    #   If the value is `true`, the field will be mapped to the same name
    #   If the value is an array, it will be mapped to a nested structure.
    #   If the value is a callable object, it will be called with the value and should return a hash that will be merged into the JSON document.
    #   If the value is `false`, the field will not be included in the JSON output.
    # @return [void]
    def mapping=(mapping)
      @mutex.synchronize do
        keys = {}
        mapping.each do |key, value|
          if value == true
            value = key.to_s.split(".")
            value = value.first if value.size == 1
          end
          keys[key.to_sym] = value if value
        end

        @time_key = keys.delete(:time)
        @severity_key = keys.delete(:severity)
        @message_key = keys.delete(:message)
        @progname_key = keys.delete(:progname)
        @pid_key = keys.delete(:pid)
        @attributes_key = keys.delete(:attributes)
        @custom_keys = keys.map do |name, key|
          [name.to_s.split("."), key]
        end.to_h

        @mapping = mapping
      end
    end

    # Add a field mapping to the existing mappings.
    #
    # @param field_mapping [Hash] A hash where the key is the log entry field name and the value is the JSON key.
    #   If the value is `true`, the field will be mapped to the same name
    #   If the value is an array, it will be mapped to a nested structure.
    #   If the value is a callable object, it will be called with the value and should return a hash that will be merged into the JSON document.
    #   If the value is `false`, the field will not be included in the JSON output.
    # @return [void]
    def map(field_mapping)
      new_mapping = field_mapping.transform_keys(&:to_sym)
      self.mapping = mapping.merge(new_mapping)
    end

    # Convert a Lumberjack::LogEntry to a Hash using the specified field mapping.
    #
    # @param entry [Lumberjack::LogEntry] The log entry to convert.
    # @return [Hash] A hash representing the log entry in JSON format.
    def entry_as_json(entry)
      data = {}
      set_attribute(data, @time_key, entry.time) if @time_key
      set_attribute(data, @severity_key, entry.severity_label) if @severity_key
      set_attribute(data, @message_key, json_safe(entry.message)) if @message_key
      set_attribute(data, @progname_key, json_safe(entry.progname)) if @progname_key && entry.progname
      set_attribute(data, @pid_key, entry.pid) if @pid_key

      attributes = entry.attributes.transform_values { |value| json_safe(value) } if entry.attributes

      if @custom_keys.size > 0 && attributes && !attributes&.empty?
        @custom_keys.each do |name, key|
          name = name.is_a?(Array) ? name.join(".") : name.to_s
          value = attributes.delete(name)
          next if value.nil?

          value = Lumberjack::Utils.expand_attributes(value) if value.is_a?(Hash)
          set_attribute(data, key, value)
        end
      end

      if @attributes_key && !attributes&.empty?
        attributes = Lumberjack::Utils.expand_attributes(attributes)
        if @attributes_key == "*"
          attributes.each { |k, v| data[k] = v unless data.include?(k) }
        else
          set_attribute(data, @attributes_key, attributes)
        end
      end

      data = @formatter.format(data) if @formatter
      if @post_processor
        processed_result = @post_processor.call(data)
        data = processed_result if processed_result.is_a?(Hash)
      end

      data
    end

    private

    def output_stream(output, options)
      output ||= $stdout

      if output.is_a?(Lumberjack::Device)
        output
      elsif output.is_a?(String) || (defined?(Pathname) && output.is_a?(Pathname))
        options = options.slice(:binmode, :autoflush, :shift_age, :shift_size, :shift_period_suffix)
        Lumberjack::Device::LogFile.new(output, options)
      else
        if output == :stdout
          output = $stdout
        elsif output == :stderr
          output = $stderr
        end
        options = options.slice(:binmode, :autoflush)
        Lumberjack::Device::Writer.new(output, options)
      end
    end

    def default_formatter
      Lumberjack::Formatter.build do |formatter|
        formatter.add(::Enumerable, Lumberjack::Formatter::StructuredFormatter.new(formatter))
        formatter.add(::Object) { |value| json_safe(value) }
      end
    end

    def time_formatter(datetime_format: nil, force_utc: false)
      lambda do |time|
        time = time.utc if force_utc && !time.utc?
        datetime_format ? time.strftime(datetime_format) : time
      end
    end

    def set_attribute(data, key, value)
      return if value.nil?

      key = key.split(".") if key.is_a?(String) && key.include?(".")

      if key.is_a?(Array)
        unless key.empty?
          if key.size == 1
            data[key.first] = value
          else
            data[key.first] ||= {}
            set_attribute(data[key.first], key[1, key.size], value)
          end
        end
      elsif key.respond_to?(:call)
        hash = key.call(value)
        if hash.is_a?(Hash)
          deep_merge!(data, hash)
        end
      else
        data[key.to_s] = value unless key.nil?
      end
    end

    def deep_merge!(hash, other_hash, &block)
      other_hash = other_hash.transform_keys(&:to_s)
      hash.merge!(other_hash) do |key, this_val, other_val|
        if this_val.is_a?(Hash) && other_val.is_a?(Hash)
          deep_merge!(this_val, other_val, &block)
        elsif block
          block.call(key, this_val, other_val)
        else
          other_val
        end
      end
    end

    def json_safe(value, seen = nil)
      return value if JSON_NATIVE_CLASSES.include?(value.class)
      return nil if seen&.include?(value.object_id)

      # Check if the as_json method is defined and takes no parameters
      as_json_arity = value.method(:as_json).arity if !value.nil? && value.respond_to?(:as_json)

      if as_json_arity == 0 || as_json_arity == -1
        value.as_json
      elsif !value.is_a?(Enumerable)
        value
      else
        seen ||= Set.new
        seen << value.object_id
        if value.is_a?(Hash)
          value.transform_values { |v| json_safe(v, seen) }
        else
          value.collect { |v| json_safe(v, seen) }
        end
      end
    rescue SystemStackError, StandardError => e
      error_message = e.class.name
      error_message = "#{error_message} #{e.message}" if e.message && e.message != ""
      warn("<Error serializing #{value.class} to JSON: #{error_message}>")
      "<Error serializing #{value.class} to JSON: #{error_message}>"
    end
  end
end
