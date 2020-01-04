require 'spec_helper'

describe Lumberjack::JsonDevice do

  let(:output) { StringIO.new }
  let(:entry){ Lumberjack::LogEntry.new(Time.now, Logger::INFO, "message", "test", 12345, "foo" => "bar", "baz" => "boo") }

  describe "entry_as_json" do
    it "should have a default mapping of the entry fields" do
      device = Lumberjack::JsonDevice.new(output)
      data = device.entry_as_json(entry)
      expect(data).to eq({
        "time" => entry.time,
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
        "timestamp" => entry.time,
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
        "timestamp" => entry.time,
        "level" => entry.severity_label,
        "app" => entry.progname,
        "pid" => entry.pid,
        "message" => entry.message,
        "payload" => { "baz" => "boo" },
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
        "timestamp" => entry.time,
        "level" => entry.severity_label,
        "process" => { "name" => entry.progname, "pid" => entry.pid },
        "payload" => { "message" => entry.message, "tags" => entry.tags }
      })
    end

    it "should be able to map with a proc" do
      mapping = {
        time: lambda { |t| {timestamp: t.to_i} },
        severity: "level",
        message: lambda { |m| {text: m, size: m.size}}
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
      expect(lines).to eq [MultiJson.dump(data)] * 2
    end

    it "should wrap a stream" do
      device = Lumberjack::JsonDevice.new(output)
      device.write(entry)
      device.write(entry)
      device.flush
      lines = output.string.chomp.split(Lumberjack::LINE_SEPARATOR)
      data = device.entry_as_json(entry)
      expect(lines).to eq [MultiJson.dump(data)] * 2
    end
  end

  describe "formatter" do
    it "should apply a formatter to the data objects" do
      formatter = Lumberjack::Formatter.new
      formatter.add(Time) { |obj| "#{obj}!" }
      device = Lumberjack::JsonDevice.new(output, formatter: formatter, mapping: {time: "time", message: "message"})
      device.write(entry)
      line = output.string.chomp
      expect(line).to eq MultiJson.dump("time" => "#{entry.time}!", "message" => "message")
    end
  end

  describe "datetime_format" do
    it "should get and set the datetime_format" do
      device = Lumberjack::JsonDevice.new(output, mapping: {time: "time", message: "message"})
      expect(device.datetime_format).to eq nil
      device.datetime_format = "%Y-%m-%d--%H.%M.%S"
      expect(device.datetime_format).to eq "%Y-%m-%d--%H.%M.%S"
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
      expect(MultiJson.load(line)).to eq({"time" => time_1.strftime(format), "message" => time_2.strftime(format), "app" => "test"})
    end
  end

end
