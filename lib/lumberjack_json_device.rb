# frozen_string_literal: true

require 'lumberjack'
require 'multi_json'
require 'thread'

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
    attr_reader :mapping

    def initialize(stream_or_device, mapping: DEFAULT_MAPPING, formatter: nil, datetime_format: nil)
      @mutex = Mutex.new

      if stream_or_device.is_a?(Device)
        @device = stream_or_device
      else
        @device = Writer.new(stream_or_device)
      end

      self.mapping = mapping

      if formatter
        @formatter = formatter
      else
        @formatter = default_formatter
        datetime_format = DEFAULT_TIME_FORMAT if datetime_format.nil?
      end
      add_datetime_formatter!(datetime_format) unless datetime_format.nil?
    end

    def write(entry)
      data = entry_as_json(entry)
      json = MultiJson.dump(data)
      @device.write(json)
    end

    def flush
      @device.flush
    end

    def datetime_format
      @datetime_format
    end

    # Set the datetime format for the log timestamp.
    def datetime_format=(format)
      add_datetime_formatter!(format)
    end

    # Set the mapping for how to map an entry to a JSON object.
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
        @custom_keys = keys
        @mapping = mapping
      end
      nil
    end

    def map(field_mapping)
      new_mapping = {}
      field_mapping.each do |key, value|
        new_mapping[key.to_sym] = value
      end
      self.mapping = mapping.merge(new_mapping)
    end

    # Convert a Lumberjack::LogEntry to a Hash using the specified field mapping.
    def entry_as_json(entry)
      data = {}
      set_attribute(data, @time_key, entry.time) unless @time_key.nil?
      set_attribute(data, @severity_key, entry.severity_label) unless @severity_key.nil?
      set_attribute(data, @progname_key, entry.progname) unless @progname_key.nil?
      set_attribute(data, @pid_key, entry.pid) unless @pid_key.nil?
      set_attribute(data, @message_key, entry.message) unless @message_key.nil?

      tags = entry.tags
      if @custom_keys.size > 0
        tags = (tags.nil? ? {} : tags.dup)
        @custom_keys.each do |name, key|
          set_attribute(data, key, tags.delete(name.to_s))
        end
      end

      unless @tags_key.nil?
        tags ||= {}
        set_attribute(data, @tags_key, tags)
      end

      data = @formatter.format(data) if @formatter
      data
    end

    private

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
        elsif block_given?
          block.call(key, this_val, other_val)
        else
          other_val
        end
      end
    end

  end
end
