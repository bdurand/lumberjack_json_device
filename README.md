# Lumberjack JSON Device

[![Build Status](https://travis-ci.org/bdurand/lumberjack_json_device.svg?branch=master)](https://travis-ci.org/bdurand/lumberjack_json_device)
[![Maintainability](https://api.codeclimate.com/v1/badges/c62cb886b86381560810/maintainability)](https://codeclimate.com/github/bdurand/lumberjack_json_device/maintainability)

This gem provides a logging device for the [lumberjack](https://github.com/bdurand/lumberjack) gem that will log JSON formatted output to a stream with one JSON document per line. This can be used as part of a log processing pipeline to ship the log to a structured data store or logging service.

## Destination

You can send the JSON output either to a stream or to another Lumberjack device.

```ruby
# Send to STDOUT
device = Lumberjack::JsonDevice.new(STDOUT)

# Send to another logging device
log_file = Lumberjack::Device::LogFile.new("/var/log/app.log")
device = Lumberjack::JsonDevice.new(log_file)
```

## JSON Structure

By default, the JSON document will map to the `Lumberjack::LogEntry` data structure.

```json
{"timestamp": "2020-01-02T19:47:45.123455", "severity": "INFO", "progname": "web", "pid": 101, "message": "test", "tags": {"foo": "bar"}}
```

You can specify a mapping to the device to customize the JSON document data structure. You can map the standard field names (time, severity, progname, pid, message, and tags) to custom field names.

If you map a field to an array, it will be mapped into a nested hash in the JSON document.

Any keys beyond the standard field names will be populated by a tag with the same name. These tags will not be included with the rest of the tags.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: "timestamp",
  severity: "level",
  progname: ["app", "name"],
  pid: ["app", "pid"],
  message: "message",
  duration: "duration",
  tags: "tags"
})
```

```json
{"timestamp": "2020-01-02T19:47:45.123455", "level": "INFO", "app": {"name": "web", "pid": 101}, "message": "test", "duration": 5, "tags": {"foo": "bar"}}
```

If you omit any fields in the mapping, they will not appear in the JSON document.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: "timestamp",
  severity: "level",
  message: "message",
})
```

```json
{"timestamp": "2020-01-02T19:47:45.123455", "level": "INFO", "message": "test"}
```

You can also provide a block or any object that responds to `call` in a mapping. The block will be called with the value and should emit a hash that will be merged into the JSON document.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: lambda { |val| (timestamp: val.to_f * 1000).round} },
  severity: "level",
  message: "test",
})
```

```json
{"timestamp": 1578125375588, "level": "INFO", "message": "test"}
```

## Data Formatting

The device will have a `Lumberjack::Formatter` that will be used to format objects before serializing them as JSON. You can add additional formatters for classes to the default formatter, or supply a custom one when creating the device.

```ruby
device.formatter.add(Exception, LumberjacK::Formatter::InspectFormatter.new)
device.formatter.add(ActiveRecord::Base, LumberjacK::Formatter::IdFormatter.new)
```

You can also specify the `datetime_format` that will be used to serialize Time and DateTime objects.

```ruby
device.datetime_format = "%Y-%m-%dT%H:%M:%S.%3N"
```
