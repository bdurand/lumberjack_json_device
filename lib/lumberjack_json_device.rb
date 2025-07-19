# frozen_string_literal: true

require "lumberjack"
require "json"

module Lumberjack
  # This Lumberjack device logs output to another device as JSON formatted text with one document per line.
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
  # * :tags
  #
  # Any additional keys will be pulled from the tags. If any of the standard keys are missing or have a nil
  # mapping, the entry field will not be included in the JSON output.
  #
  # You can create a nested JSON structure by specifying an array as the JSON key.
  class JsonDevice < Device
    DEFAULT_MAPPING = {
      time: true,
      severity: true,
      progname: true,
      pid: true,
      message: true,
      tags: true
    }.freeze

    DEFAULT_TIME_FORMAT = "%Y-%m-%dT%H:%M:%S.%6N%z"

    attr_accessor :formatter
    attr_accessor :post_processor
    attr_writer :pretty
    attr_reader :mapping

    # @param stream_or_device [IO, Lumberjack::Device] The output stream or Lumberjack device to write
    #  the JSON formatted log entries to.
    # @param mapping [Hash] A hash where the key is the log entry field name and the value indicates how
    #   to map the field if it exists. If the value is `true`, the field will be mapped to the same name.
    #   If the value is an array, it will be mapped to a nested structure that follows the array elements.
    #   If the value is a callable object, it will be called with the value and is expected to return
    #   a hash that will be merged into the JSON document.
    #   If the value is `false`, the field will not be included in the JSON output.
    # @param formatter [Lumberjack::Formatter] An optional formatter to use for formatting the log entry data.
    # @param datetime_format [String] An optional datetime format string to use for formatting the log timestamp.
    # @param post_processor [Proc] An optional callable object that will be called with the log entry hash
    #   before it is written to the output stream. This can be used to modify the log entry data
    #   before it is serialized to JSON.
    # @param pretty [Boolean] If true, the output will be formatted as pretty JSON with indentation and newlines.
    #   The default is false, which writes each log entry as a single line JSON document.
    def initialize(stream_or_device, mapping: DEFAULT_MAPPING, formatter: nil, datetime_format: nil, post_processor: nil, pretty: false)
      @mutex = Mutex.new

      @device = if stream_or_device.is_a?(Device)
        stream_or_device
      else
        Lumberjack::Device::Writer.new(stream_or_device)
      end

      self.mapping = mapping

      if formatter
        @formatter = formatter
      else
        @formatter = default_formatter
        datetime_format = DEFAULT_TIME_FORMAT if datetime_format.nil?
      end
      add_datetime_formatter!(datetime_format) unless datetime_format.nil?

      @post_processor = post_processor

      @pretty = !!pretty
    end

    def write(entry)
      return if entry.empty?

      data = entry_as_json(entry)
      json = @pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      @device.write(json)
    end

    def flush
      @device.flush
    end

    attr_reader :datetime_format

    # Set the datetime format for the log timestamp.
    #
    # @param format [String] The datetime format string to use for formatting the log timestamp.
    def datetime_format=(format)
      add_datetime_formatter!(format)
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
        @progname_key = keys.delete(:progname)
        @pid_key = keys.delete(:pid)
        @message_key = keys.delete(:message)
        @tags_key = keys.delete(:tags)
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
      set_attribute(data, @message_key, entry.message) if @message_key
      set_attribute(data, @progname_key, entry.progname) if @progname_key
      set_attribute(data, @pid_key, entry.pid) if @pid_key

      tags = dereference_tags(entry.tags) if entry.tags
      extracted_tags = nil
      if @custom_keys.size > 0 && !tags&.empty?
        extracted_tags = []
        @custom_keys.each do |name, key|
          set_attribute(data, key, tag_value(tags, name))
          extracted_tags << name
        end

        extracted_tags.each do |path|
          tags = deep_remove_tag(tags, path, entry.tags)
        end
      end

      if @tags_key
        tags ||= {}
        if @tags_key == "*"
          data = tags.merge(data) unless tags.empty?
        else
          set_attribute(data, @tags_key, tags)
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

    def dereference_tags(tags)
      updated_tags = nil
      remove_tags = nil

      tags.each do |original_key, value|
        updated_tags ||= tags.dup unless original_key.is_a?(String)
        key = original_key.to_s

        dot_index = key.index(".")
        if dot_index
          remove_tags ||= []
          remove_tags << original_key
          updated_tags ||= tags.dup
          sub_key = key[dot_index + 1..-1]
          key = key[0, dot_index]
          existing_vals = updated_tags[key]
          unless existing_vals.is_a?(Hash)
            existing_vals = {}
            updated_tags[key] = existing_vals
          end
          existing_vals.merge!(dereference_tags({sub_key => value}))
        elsif value.is_a?(Enumerable)
          updated_tags ||= tags.dup
          updated_tags[key] = if value.is_a?(Hash)
            dereference_tags(value)
          else
            value.collect { |v| v.is_a?(Hash) ? dereference_tags(v) : v }
          end
        elsif updated_tags
          updated_tags[key] = value
        end
      end

      return tags unless updated_tags

      remove_tags&.each { |key| updated_tags.delete(key) }
      updated_tags
    end

    def tag_value(tags, name)
      return nil if tags.nil?
      return tags[name] unless name.is_a?(Array)

      val = tags[name.first]
      return val if name.length == 1
      return nil unless val.is_a?(Hash)

      tag_value(val, name[1, name.length])
    end

    def deep_remove_tag(tags, path, original_tags)
      return nil if tags.nil?

      dup_needed = tags.equal?(original_tags)
      key = path.first
      val = tags[key] if path.length > 1
      unless val.is_a?(Hash)
        if tags.include?(key)
          tags = tags.dup if dup_needed
          tags.delete(key)
        end
        return tags
      end

      new_val = deep_remove_tag(val, path[1, path.length], original_tags[key])
      if new_val.empty? || !new_val.equal?(val)
        tags = tags.dup if dup_needed
        if new_val.empty?
          tags.delete(key)
        else
          tags[key] = new_val
        end
      end

      tags
    end

    def set_attribute(data, key, value)
      return if value.nil?

      if (value.is_a?(Time) || value.is_a?(DateTime)) && @time_formatter
        value = @time_formatter.call(value)
      end

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
          deep_merge!(data, Lumberjack::Tags.stringify_keys(hash))
        end
      else
        data[key] = value unless key.nil?
      end
    end

    def default_formatter
      formatter = Formatter.new.clear
      object_formatter = Lumberjack::Formatter::ObjectFormatter.new
      formatter.add(String, object_formatter)
      formatter.add(Object, object_formatter)
      formatter.add(Enumerable, Formatter::StructuredFormatter.new(formatter))
      formatter
    end

    def add_datetime_formatter!(datetime_format)
      if datetime_format
        @datetime_format = datetime_format
        time_formatter = Lumberjack::Formatter::DateTimeFormatter.new(datetime_format)
        formatter.add(Time, time_formatter)
        formatter.add(Date, time_formatter)
      else
        @datetime_format = nil
        formatter.remove(Time)
        formatter.remove(Date)
      end
    end

    def deep_merge!(hash, other_hash, &block)
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
  end
end
