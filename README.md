# Lumberjack JSON Device

[![Continuous Integration](https://github.com/bdurand/lumberjack_json_device/actions/workflows/continuous_integration.yml/badge.svg)](https://github.com/bdurand/lumberjack_json_device/actions/workflows/continuous_integration.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/testdouble/standard)
[![Gem Version](https://badge.fury.io/rb/lumberjack_json_device.svg)](https://badge.fury.io/rb/lumberjack_json_device)

This gem provides a logging device for the [lumberjack](https://github.com/bdurand/lumberjack) gem that outputs JSON formatted log entries to a stream with one JSON document per line. This format is ideal for structured logging pipelines and can be easily consumed by log aggregation services, search engines, and monitoring tools.

## Quick Start

```ruby
require 'lumberjack_json_device'

# Create a logger with JSON output to STDOUT
logger = Lumberjack::Logger.new(Lumberjack::JsonDevice.new(STDOUT))

# Log a message with tags
logger.info("User logged in", user_id: 123, session_id: "abc")
# Output: {"time":"2020-01-02T19:47:45.123455-0800","severity":"INFO","progname":null,"pid":12345,"message":"User logged in","tags":{"user_id":123,"session_id":"abc"}}
```

## Output Destinations

You can send the JSON output to either a stream or to another Lumberjack device.

```ruby
# Send to STDOUT
device = Lumberjack::JsonDevice.new(STDOUT)

# Send to another logging device
log_file = Lumberjack::Device::LogFile.new("/var/log/app.log")
device = Lumberjack::JsonDevice.new(log_file)
```

## JSON Structure

By default, the JSON document maps to the `Lumberjack::LogEntry` data structure and includes all standard fields:

```json
{"time": "2020-01-02T19:47:45.123455-0800", "severity": "INFO", "progname": "web", "pid": 101, "message": "test", "tags": {"foo": "bar"}}
```

### Custom Field Mapping

You can customize the JSON document structure by providing a mapping that specifies how log entry fields should be transformed. The mapping supports several different value types:

- **String**: Maps the field to a custom JSON key name
- **Array**: Creates nested JSON structures
- **`true`**: Maps the field to the same name as the key
- **`false`**: Excludes the field from the JSON output
- **Callable**: Transforms the value using custom logic

You can map the standard field names (`time`, `severity`, `progname`, `pid`, `message`, and `tags`) as well as extract specific tags by name.

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: "timestamp",
  severity: "level",
  progname: ["app", "name"],
  pid: ["app", "pid"],
  message: "message",
  duration: "duration",  # Extracts the "duration" tag
  tags: "tags"
})
```

```json
{"timestamp": "2020-01-02T19:47:45.123455-0800", "level": "INFO", "app": {"name": "web", "pid": 101}, "message": "test", "duration": 5, "tags": {"foo": "bar"}}
```

### Excluding Fields

If you omit fields from the mapping or set them to `false`, they will not appear in the JSON output:

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: "timestamp",
  severity: "level",
  message: "message",
  pid: false  # Exclude PID from output
})
```

```json
{"timestamp": "2020-01-02T19:47:45.123455-0800", "level": "INFO", "message": "test"}
```

### Custom Transformations

You can provide a callable object (proc, lambda, or any object responding to `call`) to transform field values. The callable receives the original value and should return a hash that will be merged into the JSON document:

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

### Shortcut Mapping

Use `true` as a shortcut to map a field to the same name:

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  time: "timestamp",
  severity: true,      # Maps to "severity"
  progname: true,      # Maps to "progname"
  pid: false,          # Excluded from output
  message: "message",
  tags: true          # Maps to "tags"
})
```

### Tag Extraction and Dot Notation

You can extract specific tags from the log entry and map them to custom locations in the JSON. Tags with dot notation in their names are automatically expanded into nested structures:

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  "message" => true,
  "http.status" => true,    # Extracts "http.status" tag
  "http.method" => true,    # Extracts "http.method" tag
  "http.path" => true,      # Extracts "http.path" tag
  "tags" => true
})
```

```json
{"message": "test", "http": {"status": 200, "method": "GET", "path": "/resource"}, "tags": {"other": "values"}}
```

**Important**: All tags are automatically expanded from dot notation into nested hash structures, not just extracted tags. For example, if you have a tag named `"user.profile.name"`, it will automatically become `{"user": {"profile": {"name": "value"}}}` in the tags section.

### Flattening Tags to Root Level

Use `"*"` as the tags mapping value to copy all remaining tags directly to the root level of the JSON document:

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, mapping: {
  "message" => true,
  "tags" => "*"
})
```

```json
{"message": "test", "tag1": "value", "tag2": "value"}
```

## Data Formatting

The device includes a `Lumberjack::Formatter` that formats objects before serializing them as JSON. You can add custom formatters for specific classes or supply your own formatter when creating the device.

```ruby
device.formatter.add(Exception, Lumberjack::Formatter::InspectFormatter.new)
device.formatter.add(ActiveRecord::Base, Lumberjack::Formatter::IdFormatter.new)
```

### Dynamic Mapping

You can incrementally add field mappings after creating the device using the `map` method:

```ruby
device.map(duration: "response_time", user_id: ["user", "id"])
```

### DateTime Formatting

You can specify the `datetime_format` that will be used to serialize Time and DateTime objects:

```ruby
device.datetime_format = "%Y-%m-%dT%H:%M:%S.%3N"
```

### Post Processing

You can provide a post processor that will be called on the hash before it is serialized to JSON. This allows you to modify any aspect of the log entry:

```ruby
# Filter out sensitive elements using Rails parameter filter
param_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
device = Lumberjack::JsonDevice.new(STDOUT, post_processor: ->(data) { param_filter.filter(data) }
```

Note that all hash keys will be strings.If the post processor does not return a hash, it will be ignored.

### Pretty Printing

For development or debugging, you can format the JSON output with indentation and newlines by setting the `pretty` option to `true`:

```ruby
device = Lumberjack::JsonDevice.new(STDOUT, pretty: true)
```

This will format each log entry as multi-line JSON instead of single-line output. You can check if pretty formatting is enabled using the `pretty?` method:

```ruby
device.pretty?  # => true or false
```

### Empty Messages

Log entries with empty or nil messages will not be written to the output.

## Configuration Options

The `JsonDevice` constructor accepts the following options:

- **`mapping`**: Hash defining how log fields should be mapped to JSON (default: maps all standard fields)
- **`formatter`**: Custom `Lumberjack::Formatter` instance for formatting values before JSON serialization
- **`datetime_format`**: String format for Time/DateTime objects (default: `"%Y-%m-%dT%H:%M:%S.%6N%z"`)
- **`post_processor`**: Callable that receives and can modify the final hash before JSON serialization
- **`pretty`**: Boolean to enable pretty-printed JSON output (default: `false`)

```ruby
device = Lumberjack::JsonDevice.new(
  STDOUT,
  mapping: { time: "timestamp", message: true, tags: "*" },
  datetime_format: "%Y-%m-%d %H:%M:%S",
  pretty: true,
  post_processor: lambda { |data| data.merge(app: "myapp") }
)
```

## Installation

Add this line to your application's Gemfile:

```ruby
gem "lumberjack_json_device"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install lumberjack_json_device
```

## Contributing

Open a pull request on GitHub.

Please use the [standardrb](https://github.com/testdouble/standard) syntax and lint your code with `standardrb --fix` before submitting.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
