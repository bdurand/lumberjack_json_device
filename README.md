# Lumberjack JSON Device

[![Build Status](https://travis-ci.org/bdurand/lumberjack_json_device.svg?branch=master)](https://travis-ci.org/bdurand/lumberjack_json_device)
[![Maintainability](https://api.codeclimate.com/v1/badges/c62cb886b86381560810/maintainability)](https://codeclimate.com/github/bdurand/lumberjack_json_device/maintainability)

This gem provides a logging device for the [lumberjack](https://github.com/bdurand/lumberjack) gem that will log JSON formatted output to a stream with one JSON document per line. This can be used as part of a log processing pipeline to ship the log to a structured data store or logging service.

## Destination

```ruby
# Send to STDOUT
device = Lumberjack::JsonDevice.new(STDOUT)

# Send to another logging device
log_file = Lumberjack::Device::LogFile.new("/var/log/app.log")
device = Lumberjack::JsonDevice.new(log_file)
```

## JSON Structure

```json
{"timestamp": "2020-01-02T19:47:45.123455", "severity": "INFO", "progname": "web", "pid": 101, "message": "test", "tags": {"foo": "bar"}}
```


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

