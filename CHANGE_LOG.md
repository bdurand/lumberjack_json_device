# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 2.0.0

### Changed

- Tag structure is now consistently expanded from dot notation into nested hashes in the `tag` field. Previoulsly this was only done when the template copied tags to the root level of the JSON document.

### Removed

- Remove gem dependency on `multi_json`. The gem now uses the `JSON` code from the Ruby standard library for consistency. `JSON` is also now amoung the fastest JSON libraries available in Ruby so performance is no longer a concern.
- Removed support for Ruby versions below 2.5.

## 1.0.0

### Added

- Initial release
