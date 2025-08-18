# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.2.0

### Added

- Support for Lumberjack 2.0.

### Removed

- Support for Ruby versions less than 2.7

## 2.1.0

### Changed

- Tags that contain arrays of hashes are no longer expanded to nested hashes if the hashes in the array use dot nottion in their keys. The hashes in the array will now be included as is in JSON output.

## 2.0.0

### Added

- Field mapping for the JSON can now be set to an array where the first element is the key to map and the second element is a callable object that will transform the value.
- Output can be set to pretty for better display in development environments.
- Added post_processor option to allow custom processing of the log entry hash before it is written to the output stream.

### Changed

- Tag structure is now consistently expanded from dot notation into nested hashes in the `attribute` field. Previoulsly this was only done when the template copied attributes to the root level of the JSON document.
- The mapping options now supports setting the value to `false` to exclude a field from the JSON output.
- Tag mapping can now be set to `"*"` to copy all attributes into the root of the JSON document.

### Removed

- Remove gem dependency on `multi_json`. The gem now uses the `JSON` code from the Ruby standard library for consistency. `JSON` is also now amoung the fastest JSON libraries available in Ruby so performance is no longer a concern.
- Removed support for Ruby versions below 2.5.

## 1.0.0

### Added

- Initial release
