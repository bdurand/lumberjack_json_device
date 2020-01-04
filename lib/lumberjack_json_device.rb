# frozen_string_literal: true

require 'lumberjack'
require 'multi_json'

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
      time: "time",
      severity: "severity",
      progname: "progname",
      pid: "pid",
      message: "message",
      tags: "tags"
    }.freeze

    attr_accessor :formatter

    def initialize(stream_or_device, mapping: DEFAULT_MAPPING, formatter: nil)
      if stream_or_device.is_a?(Device)
        @device = stream_or_device
      else
        @device = Writer.new(stream_or_device)
      end

      @custom_keys = {}
      mapping.each do |key, value|
        @custom_keys[key.to_sym] = value
      end
      @time_key = @custom_keys.delete(:time)
      @severity_key = @custom_keys.delete(:severity)
      @progname_key = @custom_keys.delete(:progname)
      @pid_key = @custom_keys.delete(:pid)
      @message_key = @custom_keys.delete(:message)
      @tags_key = @custom_keys.delete(:tags)

      @formatter = (formatter || default_formatter)
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
      @time_formatter.format if @time_formatter
    end

    def datetime_format=(format)
      @time_formatter = Lumberjack::Formatter::DateTimeFormatter.new(format)
    end

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
      formatter.add(Exception, Formatter::InspectFormatter.new)
    end

    def deep_merge!(hash, other_hash, &block)
      hash.merge!(other_hash) do |key, this_val, other_val|
        if this_val.is_a?(Hash) && other_val.is_a?(Hash)
          deep_merge(this_val, other_val, &block)
        elsif block_given?
          block.call(key, this_val, other_val)
        else
          other_val
        end
      end
    end

  end
end
