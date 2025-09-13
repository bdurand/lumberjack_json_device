# frozen_string_literal: true

require "spec_helper"

RSpec.describe Lumberjack::JsonDevice do
  let(:output) { StringIO.new }
  let(:entry) { Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => "boo") }

  describe "VERSION" do
    it "has a version number" do
      expect(Lumberjack::JsonDevice::VERSION).not_to be nil
    end
  end

  describe "registry" do
    it "should register the device" do
      expect(Lumberjack::DeviceRegistry.device_class(:json)).to eq(Lumberjack::JsonDevice)
    end
  end

  describe "output stream" do
    it "outputs to STDOUT by default" do
      device = Lumberjack::JsonDevice.new
      expect(device.dev).to eq($stdout)
    end

    it "outputs to the stream specified in the :output option" do
      device = Lumberjack::JsonDevice.new(output: output)
      expect(device.dev).to eq output
    end

    it "outputs to the file in the :output option" do
      log_file_path = Tempfile.new("logfile").path
      begin
        device = Lumberjack::JsonDevice.new(output: log_file_path)
        expect(device.dev.path).to eq log_file_path
      ensure
        File.delete(log_file_path)
      end
    end

    it "can specify a Writer device" do
      writer = Lumberjack::Device::Writer.new(output)
      device = Lumberjack::JsonDevice.new(output: writer)
      expect(device.dev).to eq output
    end

    it "can specify a LoggerFile device" do
      log_file_path = Tempfile.new("logfile").path
      log_file = Lumberjack::Device::LoggerFile.new(log_file_path)
      begin
        device = Lumberjack::JsonDevice.new(output: log_file)
        expect(device.dev).to eq log_file.dev
      ensure
        log_file.close
        File.delete(log_file_path)
      end
    end

    it "can specify the stream as the first argument (deprecated)" do
      Lumberjack::Utils.with_deprecation_mode(:silent) do
        device = Lumberjack::JsonDevice.new(output: output, pretty: true)
        expect(device.dev).to eq output
        expect(device.pretty?).to be true
      end
    end

    it "can specify :stdout" do
      save_stdout = $stdout
      stdout = StringIO.new
      device = nil
      begin
        $stdout = stdout
        device = Lumberjack::JsonDevice.new(output: :stdout)
      ensure
        $stdout = save_stdout
      end

      expect(device.dev).to eq stdout
    end

    it "can specify :stderr" do
      save_stderr = $stderr
      stderr = StringIO.new
      device = nil
      begin
        $stderr = stderr
        device = Lumberjack::JsonDevice.new(output: :stderr)
      ensure
        $stderr = save_stderr
      end

      expect(device.dev).to eq stderr
    end
  end

  describe "entry_as_json" do
    it "should have a default mapping of the entry fields" do
      device = Lumberjack::JsonDevice.new(output: output)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "time" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "severity" => entry.severity_label,
        "progname" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "attributes" => entry.attributes
      })
    end

    it "can map attributes to tags for compatibility with release < 3.0" do
      mapping = {
        time: true,
        severity: true,
        progname: true,
        pid: true,
        message: true,
        attributes: ["tags"]
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "time" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "severity" => entry.severity_label,
        "progname" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "tags" => entry.attributes
      })
    end

    it "should not include unmapped fields" do
      mapping = {
        message: "message"
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message})
    end

    it "should not include nil attributes" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        attributes: "attributes"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => nil)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "attributes" => {"foo" => "bar"}})
    end

    it "should not include empty hashes in attributes" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        attributes: "attributes"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => {})
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "attributes" => {"foo" => "bar"}})
    end

    it "should not include empty arrays in attributes" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        attributes: "attributes"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => [])
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "attributes" => {"foo" => "bar"}})
    end

    it "should include false attributes" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        attributes: "attributes"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => false)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "attributes" => {"foo" => "bar", "baz" => false}})
    end

    it "should be able to map to custom JSON fields" do
      mapping = {
        time: "timestamp",
        severity: "level",
        progname: "app",
        pid: "pid",
        message: "message",
        attributes: "payload"
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "level" => entry.severity_label,
        "app" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "payload" => entry.attributes
      })
    end

    it "should be able to pull attributes out to the main JSON document" do
      mapping = {
        time: "timestamp",
        severity: "level",
        progname: "app",
        pid: "pid",
        message: "message",
        attributes: "payload",
        foo: "custom"
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "level" => entry.severity_label,
        "app" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "payload" => {"baz" => "boo"},
        "custom" => "bar"
      })
    end

    it "should be able to nest attributes in the JSON document" do
      mapping = {
        time: "timestamp",
        severity: "level",
        progname: ["process", "name"],
        pid: "process.pid",
        message: ["payload", "message"],
        attributes: ["payload", "attributes"]
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "level" => entry.severity_label,
        "process" => {"name" => entry.progname, "pid" => entry.pid},
        "payload" => {"message" => entry.message, "attributes" => entry.attributes}
      })
    end

    it "should be able to transform a value with a proc" do
      mapping = {
        time: lambda { |t| {timestamp: t.to_i} },
        severity: "level",
        message: lambda { |m| {text: m, size: m.size} }
      }
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.to_i,
        "level" => entry.severity_label,
        "text" => entry.message,
        "size" => entry.message.size
      })
    end

    it "should use a 1:1 mapping if the mapped value is true" do
      mapping = {
        severity: true,
        message: true,
        "foo.bar": true,
        attributes: true
      }
      attributes = Lumberjack::Utils.flatten_attributes({
        "foo" => {"bar" => "boo"},
        "baz" => "bip"
      })
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "foo" => {"bar" => "boo"},
        "attributes" => {
          "baz" => "bip"
        }
      })
    end

    it "should not include values if the mapping is set to nil" do
      mapping = {
        severity: true,
        message: true,
        progname: nil
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar")
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message
      })
    end

    it "should not include values if the mapping is set to false" do
      mapping = {
        severity: true,
        message: true,
        progname: false
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar")
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message
      })
    end

    it "should nest attributes in the JSON document using dot syntax" do
      mapping = {
        severity: true,
        message: true,
        attributes: true
      }
      attributes = {
        "bip" => "bap",
        "foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "attributes" => {
          "bip" => "bap",
          "foo" => {"bar" => "boo"},
          "mip" => "map"
        }
      })
    end

    it "moves attributes to the root level if the attributes key is set to '*'" do
      mapping = {
        severity: true,
        message: true,
        attributes: "*"
      }
      attributes = {
        "foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "foo" => {"bar" => "boo"},
        "mip" => "map"
      })
    end

    it "cannot override explicit root values with splat attributes" do
      mapping = {
        severity: true,
        message: true,
        attributes: "*"
      }
      attributes = {
        "severity" => "fatal",
        "message" => "Go west young man",
        "foo" => "bar"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "foo" => "bar"
      })
    end

    it "converts attributes names to strings" do
      mapping = {
        severity: true,
        message: true,
        attributes: true
      }
      attributes = {
        "bip" => "bap",
        :"foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "attributes" => {
          "bip" => "bap",
          "foo" => {"bar" => "boo"},
          "mip" => "map"
        }
      })
    end

    it "dereferences nested attributes" do
      mapping = {
        severity: true,
        message: true,
        attributes: true
      }
      attributes = {
        "foo.bar.baz" => "boo",
        "mip" => {"mop.mip" => "map"}
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "attributes" => {
          "foo" => {"bar" => {"baz" => "boo"}},
          "mip" => {"mop" => {"mip" => "map"}}
        }
      })
    end

    it "can handle mixed dot notation and structured attributes with dot notation attributes first" do
      mapping = {
        severity: true,
        message: true,
        attributes: true
      }
      attributes = {
        "foo.bar" => "baz",
        "foo" => {"bip" => "bop"},
        "foo.quz" => {"wap.woop" => "wop"}
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      expanded_attributes = device.entry_as_json(entry)["attributes"]
      expect(expanded_attributes).to eq({
        "foo" => {
          "bar" => "baz",
          "bip" => "bop",
          "quz" => {"wap" => {"woop" => "wop"}}
        }
      })
    end

    it "can handle mixed dot notation and structured attributes with structured attributes first" do
      mapping = {
        severity: true,
        message: true,
        attributes: true
      }
      attributes = {
        "foo" => {"bar" => "baz"},
        "foo.bip" => "bop",
        "foo.quz" => {"wap.woop" => "wop"}
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, attributes)
      device = Lumberjack::JsonDevice.new(output: output, mapping: mapping)
      expanded_attributes = device.entry_as_json(entry)["attributes"]
      expect(expanded_attributes).to eq({
        "foo" => {
          "bar" => "baz",
          "bip" => "bop",
          "quz" => {"wap" => {"woop" => "wop"}}
        }
      })
    end
  end

  describe "device output" do
    it "should not write out empty log messages" do
      blank_entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "", "test", 12345, {})
      nil_entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, nil, "test", 12345, nil)
      device = Lumberjack::JsonDevice.new(output: output)
      device.write(blank_entry)
      device.write(nil_entry)
      device.flush
      lines = output.string.chomp.split(Lumberjack::LINE_SEPARATOR)
      expect(lines).to eq []
    end

    it "should write one document per line" do
      entry_1 = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "line_1\nline_2", "test", 12345, "foo" => {"bar" => "line_1\nline_2"})
      entry_2 = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "entry_2", "test", 12345, nil)
      device = Lumberjack::JsonDevice.new(output: output)
      device.write(entry_1)
      device.write(entry_2)
      device.flush
      lines = output.string.chomp.split("\n")
      data = device.entry_as_json(entry)
      expect(lines.length).to eq 2
      expect(JSON.parse(lines.first)["message"]).to eq "line_1\nline_2"
      expect(JSON.parse(lines.last)["message"]).to eq "entry_2"
    end

    it "should allow writing out pretty JSON" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "pretty", "test", 12345, "foo" => {"bar" => "baz"})
      device = Lumberjack::JsonDevice.new(output: output, pretty: true)
      device.write(entry)
      device.flush
      lines = output.string.chomp
      data = device.entry_as_json(entry)
      expect(lines).to eq JSON.pretty_generate(data)
    end

    it "should write out dot notation attributes from log messages as nested JSON" do
      device = Lumberjack::JsonDevice.new(output: output)
      logger = Lumberjack::Logger.new(device)
      logger.info("message", "foo.bar" => "baz", "foo.baz" => "boo")
      logger.flush
      json = JSON.parse(output.string.chomp.split(Lumberjack::LINE_SEPARATOR).last)
      expect(json.dig("attributes", "foo", "bar")).to eq "baz"
      expect(json.dig("attributes", "foo", "baz")).to eq "boo"
    end
  end

  describe "formatter" do
    it "should apply a formatter to the data objects" do
      formatter = Lumberjack::Formatter.new
      formatter.add(String) { |obj| "#{obj}!" }
      formatter.add(Time) { |obj| obj.iso8601 }
      device = Lumberjack::JsonDevice.new(output: output, formatter: formatter, mapping: {time: "time", message: "message", foo: "foo"})
      device.write(entry)
      line = output.string.chomp
      expect(line).to eq JSON.generate("time" => entry.time.iso8601, "message" => "message!", "foo" => "bar!")
    end
  end

  describe "datetime_format" do
    it "should get and set the datetime_format" do
      device = Lumberjack::JsonDevice.new(output: output, mapping: {time: "time", message: "message"})
      expect(device.datetime_format).to eq "%Y-%m-%dT%H:%M:%S.%6N%z"
      device.datetime_format = "%Y-%m-%d--%H.%M.%S"
      expect(device.datetime_format).to eq "%Y-%m-%d--%H.%M.%S"
    end

    it "should get and set the datetime_format in the constructor" do
      device = Lumberjack::JsonDevice.new(output: output, mapping: {time: "time", message: "message"}, datetime_format: "%Y-%m-%d")
      expect(device.datetime_format).to eq "%Y-%m-%d"
      expect(device.datetime_format).to eq "%Y-%m-%d"
    end

    it "should apply the datetime_format to all datetime fields in the JSON" do
      format = "%Y-%m-%d--%H.%M.%S"
      device = Lumberjack::JsonDevice.new(output: output, mapping: {time: "time", message: "message", progname: "app"})
      device.datetime_format = format
      time_1 = Time.now
      time_2 = Time.now
      entry = Lumberjack::LogEntry.new(time_1, Logger::INFO, time_2, "test", 12345, {})
      device.write(entry)
      device.flush
      line = output.string.chomp
      expect(JSON.parse(line)).to eq({"time" => time_1.strftime(format), "message" => time_2.strftime(format), "app" => "test"})
    end

    it "can force UTC values" do
      device = Lumberjack::JsonDevice.new(output: output, utc: true)
      time = Time.parse("2025-08-27T12:45:56-0700")
      entry = Lumberjack::LogEntry.new(time, Logger::INFO, "test", "app", 12345, {})
      device.write(entry)
      device.flush
      line = output.string.chomp
      expect(JSON.parse(line)["time"]).to eq time.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N%z")
    end
  end

  describe "mapping" do
    it "should be able to change the mapping" do
      device = Lumberjack::JsonDevice.new(output: output, mapping: {message: "message"})
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message})

      device.mapping = device.mapping.merge(message: "text", severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"text" => entry.message, "level" => "INFO"})
    end

    it "should be able to add to the mapping" do
      device = Lumberjack::JsonDevice.new(output: output, mapping: {message: "message"})
      device.mapping = device.map(message: "text", severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"text" => entry.message, "level" => "INFO"})
    end

    it "should remove from the mapping with falsey value" do
      device = Lumberjack::JsonDevice.new(output: output, mapping: {message: "message"})
      device.mapping = device.map(message: false, severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"level" => "INFO"})
    end
  end

  describe "as_json support" do
    let(:obj) do
      Object.new.tap do |o|
        def o.as_json(options = nil)
          {"foo" => "bar"}
        end
      end
    end

    it "calls as_json on the message" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, obj, nil, 12345, {})
      device = Lumberjack::JsonDevice.new(output: output, mapping: {message: "message"})
      device.write(entry)
      line = output.string.chomp
      expect(JSON.parse(line)["message"]).to eq({"foo" => "bar"})
    end

    it "calls as_json on the progname" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", obj, 12345, {})
      device = Lumberjack::JsonDevice.new(output: output, mapping: {progname: "progname"})
      device.write(entry)
      line = output.string.chomp
      expect(JSON.parse(line)["progname"]).to eq({"foo" => "bar"})
    end

    it "calls as_json on the attributes" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", "app", 12345, {"a" => obj})
      device = Lumberjack::JsonDevice.new(output: output)
      device.write(entry)
      line = output.string.chomp
      expect(JSON.parse(line)["attributes"]).to eq({"a" => {"foo" => "bar"}})
    end

    it "calls as_json on nested values" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", "app", 12345, {"a" => ["d", {"b" => obj}]})
      device = Lumberjack::JsonDevice.new(output: output)
      device.write(entry)
      line = output.string.chomp
      expect(JSON.parse(line)["attributes"]).to eq({"a" => ["d", {"b" => {"foo" => "bar"}}]})
    end

    it "ignores self references in hashes" do
      circular_reference = {"one" => 1}
      circular_reference["self"] = circular_reference
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", "app", 12345, circular_reference)
      device = Lumberjack::JsonDevice.new(output: output)
      device.write(entry)
      line = output.string.chomp
      expect(JSON.parse(line)["attributes"]).to eq({"one" => 1})
    end

    it "records an error value if the entry cannot be serialized" do
      obj = Object.new
      def obj.as_json
        as_json
      end

      save_stderr = $stderr
      begin
        $stderr = StringIO.new
        entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "test", "app", 12345, "foo" => obj)
        device = Lumberjack::JsonDevice.new(output: output)
        device.write(entry)
      ensure
        $stderr = save_stderr
      end

      line = output.string.chomp
      expect(JSON.parse(line)["attributes"]["foo"]).to include("Error serializing Object to JSON: SystemStackError")
    end
  end

  describe "post_processor" do
    it "can provide a post processor to modify the log entry before writing" do
      post_processor = ->(data) { data.transform_keys(&:upcase) }
      device = Lumberjack::JsonDevice.new(output: output, post_processor: post_processor)
      device.write(entry)
      device.flush
      json = JSON.parse(output.string.chomp)
      expect(json["MESSAGE"]).to eq entry.message
      expect(json.keys).to match_array(json.keys.collect(&:upcase))
    end

    it "ignores the post processor result if it is not a hash" do
      post_processor = ->(data) { data.delete("message") }
      device = Lumberjack::JsonDevice.new(output: output, post_processor: post_processor)
      device.write(entry)
      device.flush
      json = JSON.parse(output.string.chomp)
      expect(json).to include("time")
      expect(json).not_to include("message")
    end
  end
end
