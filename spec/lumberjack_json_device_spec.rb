require "spec_helper"

RSpec.describe Lumberjack::JsonDevice do
  let(:output) { StringIO.new }
  let(:entry) { Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => "boo") }

  describe "entry_as_json" do
    it "should have a default mapping of the entry fields" do
      device = Lumberjack::JsonDevice.new(output)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "time" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "severity" => entry.severity_label,
        "progname" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "tags" => entry.tags
      })
    end

    it "should not include unmapped fields" do
      mapping = {
        message: "message"
      }
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message})
    end

    it "should not include nil tags" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        tags: "tags"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => nil)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "tags" => {"foo" => "bar", "baz" => nil}})
    end

    it "should include false tags" do
      mapping = {
        message: "message",
        thread: ["logger", "thread"],
        tags: "tags"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => false)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message, "tags" => {"foo" => "bar", "baz" => false}})
    end

    it "should be able to map to custom JSON fields" do
      mapping = {
        time: "timestamp",
        severity: "level",
        progname: "app",
        pid: "pid",
        message: "message",
        tags: "payload"
      }
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "level" => entry.severity_label,
        "app" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "payload" => entry.tags
      })
    end

    it "should be able to pull tags out to the main JSON document" do
      mapping = {
        time: "timestamp",
        severity: "level",
        progname: "app",
        pid: "pid",
        message: "message",
        tags: "payload",
        foo: "custom"
      }
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
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
        pid: ["process", "pid"],
        message: ["payload", "message"],
        tags: ["payload", "tags"]
      }
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "timestamp" => entry.time.strftime("%Y-%m-%dT%H:%M:%S.%6N%z"),
        "level" => entry.severity_label,
        "process" => {"name" => entry.progname, "pid" => entry.pid},
        "payload" => {"message" => entry.message, "tags" => entry.tags}
      })
    end

    it "should be able to transform a value with a proc" do
      mapping = {
        time: lambda { |t| {timestamp: t.to_i} },
        severity: "level",
        message: lambda { |m| {text: m, size: m.size} }
      }
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
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
        tags: true
      }
      tags = {
        "foo" => {"bar" => "boo"},
        "baz" => "bip"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "foo" => {"bar" => "boo"},
        "tags" => {
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
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
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
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message
      })
    end

    it "should nest tags in the JSON document using dot syntax" do
      mapping = {
        severity: true,
        message: true,
        tags: true
      }
      tags = {
        "bip" => "bap",
        "foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "tags" => {
          "bip" => "bap",
          "foo" => {"bar" => "boo"},
          "mip" => "map"
        }
      })
    end

    it "moves tags to the root level if the tags key is set to '*'" do
      mapping = {
        severity: true,
        message: true,
        tags: "*"
      }
      tags = {
        "severity" => "bap",
        "foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "foo" => {"bar" => "boo"},
        "mip" => "map"
      })
    end

    it "converts tags names to strings" do
      mapping = {
        severity: true,
        message: true,
        tags: true
      }
      tags = {
        "bip" => "bap",
        :"foo.bar" => "boo",
        "mip" => "map"
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "tags" => {
          "bip" => "bap",
          "foo" => {"bar" => "boo"},
          "mip" => "map"
        }
      })
    end

    it "dereferences nested tags" do
      mapping = {
        severity: true,
        message: true,
        tags: true
      }
      tags = {
        "foo.bar.baz" => "boo",
        "mip" => {"mop.mip" => "map"}
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "tags" => {
          "foo" => {"bar" => {"baz" => "boo"}},
          "mip" => {"mop" => {"mip" => "map"}}
        }
      })
    end

    it "expands nested tags in arrays" do
      mapping = {
        severity: true,
        message: true,
        tags: true
      }
      tags = {
        "foo" => [{"bar.baz" => "boo"}, {"qux" => ["qux"]}]
      }
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, tags)
      device = Lumberjack::JsonDevice.new(output, mapping: mapping)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "severity" => entry.severity_label,
        "message" => entry.message,
        "tags" => {
          "foo" => [
            {"bar" => {"baz" => "boo"}},
            {"qux" => ["qux"]}
          ]
        }
      })
    end
  end

  describe "device wrapping" do
    it "should wrap a device" do
      writer = Lumberjack::Device::Writer.new(output)
      device = Lumberjack::JsonDevice.new(writer)
      device.write(entry)
      device.write(entry)
      device.flush
      lines = output.string.chomp.split(Lumberjack::LINE_SEPARATOR)
      data = device.entry_as_json(entry)
      expect(lines).to eq [JSON.generate(data)] * 2
    end

    it "should wrap a stream" do
      device = Lumberjack::JsonDevice.new(output)
      device.write(entry)
      device.write(entry)
      device.flush
      lines = output.string.chomp.split(Lumberjack::LINE_SEPARATOR)
      data = device.entry_as_json(entry)
      expect(lines).to eq [JSON.generate(data)] * 2
    end

    it "should not write out empty log messages" do
      blank_entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "", "test", 12345, {})
      nil_entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, nil, "test", 12345, nil)
      device = Lumberjack::JsonDevice.new(output)
      device.write(blank_entry)
      device.write(nil_entry)
      device.flush
      lines = output.string.chomp.split(Lumberjack::LINE_SEPARATOR)
      expect(lines).to eq []
    end

    it "should write one document per line" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "line_1\nline_2", "test", 12345, "foo" => {"bar" => "line_1\nline_2"})
      device = Lumberjack::JsonDevice.new(output)
      device.write(entry)
      device.flush
      lines = output.string.chomp.split("\n")
      data = device.entry_as_json(entry)
      expect(lines.length).to eq 1
      expect(lines.first).to eq JSON.generate(data)
    end

    it "should allow writing out pretty JSON" do
      entry = Lumberjack::LogEntry.new(Time.now, Logger::INFO, "pretty", "test", 12345, "foo" => {"bar" => "baz"})
      device = Lumberjack::JsonDevice.new(output, pretty: true)
      device.write(entry)
      device.flush
      lines = output.string.chomp
      data = device.entry_as_json(entry)
      expect(lines).to eq JSON.pretty_generate(data)
    end

    it "should write out dot notation tags from log messages as nested JSON" do
      device = Lumberjack::JsonDevice.new(output)
      logger = Lumberjack::Logger.new(device)
      logger.info("message", "foo.bar" => "baz", "foo.baz" => "boo")
      logger.flush
      json = JSON.parse(output.string.chomp.split(Lumberjack::LINE_SEPARATOR).last)
      expect(json.dig("tags", "foo", "bar")).to eq "baz"
      expect(json.dig("tags", "foo", "baz")).to eq "boo"
    end
  end

  describe "formatter" do
    it "should apply a formatter to the data objects" do
      formatter = Lumberjack::Formatter.new
      formatter.add(String) { |obj| "#{obj}!" }
      formatter.add(Time) { |obj| obj.iso8601 }
      device = Lumberjack::JsonDevice.new(output, formatter: formatter, mapping: {time: "time", message: "message", foo: "foo"})
      device.write(entry)
      line = output.string.chomp
      expect(line).to eq JSON.generate("time" => entry.time.iso8601, "message" => "message!", "foo" => "bar!")
    end
  end

  describe "datetime_format" do
    it "should get and set the datetime_format" do
      device = Lumberjack::JsonDevice.new(output, mapping: {time: "time", message: "message"})
      expect(device.datetime_format).to eq "%Y-%m-%dT%H:%M:%S.%6N%z"
      device.datetime_format = "%Y-%m-%d--%H.%M.%S"
      expect(device.datetime_format).to eq "%Y-%m-%d--%H.%M.%S"
    end

    it "should get and set the datetime_format in the constructor" do
      device = Lumberjack::JsonDevice.new(output, mapping: {time: "time", message: "message"}, datetime_format: "%Y-%m-%d")
      expect(device.datetime_format).to eq "%Y-%m-%d"
      expect(device.datetime_format).to eq "%Y-%m-%d"
    end

    it "should apply the datetime_format to all datetime fields in the JSON" do
      format = "%Y-%m-%d--%H.%M.%S"
      device = Lumberjack::JsonDevice.new(output, mapping: {time: "time", message: "message", progname: "app"})
      device.datetime_format = format
      time_1 = Time.now
      time_2 = Time.now
      entry = Lumberjack::LogEntry.new(time_1, Logger::INFO, time_2, "test", 12345, {})
      device.write(entry)
      device.flush
      line = output.string.chomp
      expect(JSON.parse(line)).to eq({"time" => time_1.strftime(format), "message" => time_2.strftime(format), "app" => "test"})
    end
  end

  describe "mapping" do
    it "should be able to change the mapping" do
      device = Lumberjack::JsonDevice.new(output, mapping: {message: "message"})
      data = device.entry_as_json(entry)
      expect(data).to eq({"message" => entry.message})

      device.mapping = device.mapping.merge(message: "text", severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"text" => entry.message, "level" => "INFO"})
    end

    it "should be able to add to the mapping" do
      device = Lumberjack::JsonDevice.new(output, mapping: {message: "message"})
      device.mapping = device.map(message: "text", severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"text" => entry.message, "level" => "INFO"})
    end

    it "should remove from the mapping with falsey value" do
      device = Lumberjack::JsonDevice.new(output, mapping: {message: "message"})
      device.mapping = device.map(message: false, severity: "level")
      data = device.entry_as_json(entry)
      expect(data).to eq({"level" => "INFO"})
    end
  end
end
