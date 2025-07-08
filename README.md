# Lumberjack JSON Device

[![Continuous Integration](https://github.com/bdurand/lumberjack_json_device/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_json_device/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_json_device.svg)](https://badge.fury.io/rb/lumberjack_json_device)

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
{"time": "2020-01-02T19:47:45.123455-0800", "severity": "INFO", "progname": "web", "pid": 101, "message": "test", "tags": {"foo": "bar"}}
```

You can specify a mapping to the device to customize the JSON document data structure. You can map the standard field names (time, severity, progname, pid, message, and tags) to custom field names.

If you map a field to an array, it will be mapped into a nested hash in the JSON document.

Any keys beyond the standard field names will be populated by extracting tags with the same name. These extracted tags will not be included with the rest of the tags.

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
{"timestamp": "2020-01-02T19:47:45.123455-0800", "level": "INFO", "app": {"name": "web", "pid": 101}, "message": "test", "duration": 5, "tags": {"foo": "bar"}}
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
{"timestamp": "2020-01-02T19:47:45.123455-0800", "level": "INFO", "message": "test"}
```

You can also provide a block or any object that responds to `call` in a mapping. The block will be called with the value and should return a hash that will be merged into the JSON document.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: lambda { |val| {timestamp: (val.to_f * 1000).round} },
  severity: "level",
  message: "message",
})
```

```json
{"timestamp": 1578125375588, "level": "INFO", "message": "test"}
```

Finally, you can specify `true` in the mapping as a shortcut to map the field to the same name. If the field name contains periods, it will be mapped to a nested structure.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  "message" => true,
  "http.status" => true,
  "http.method" => true,
  "http.path" => true
})
```

```json
{"message": "test", "http": {"status": 200, "method": "GET", "path": "/resource"}}
```

## Data Formatting

The device includes a `Lumberjack::Formatter` that will be used to format objects before serializing them as JSON. You can add additional formatters for specific classes to the default formatter, or supply a custom one when creating the device.

```ruby
device.formatter.add(Exception, Lumberjack::Formatter::InspectFormatter.new)
device.formatter.add(ActiveRecord::Base, Lumberjack::Formatter::IdFormatter.new)
```

You can also incrementally add the mapping after creating the device using the `map` method:

```ruby
device.map(duration: "response_time", user_id: ["user", "id"])
```

You can also specify the `datetime_format` that will be used to serialize Time and DateTime objects.

```ruby
device.datetime_format = "%Y-%m-%dT%H:%M:%S.%3N"
```

Log entries with no message will not be written to the log.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lumberjack_json_device'
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install lumberjack_json_device
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
