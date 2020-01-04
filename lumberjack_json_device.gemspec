Gem::Specification.new do |spec|
  spec.name = 'lumberjack_json_device'
  spec.version = File.read(File.expand_path("../VERSION", __FILE__)).strip
  spec.authors = ['Brian Durand']
  spec.email = ['bbdurand@gmail.com']

  spec.summary = "A logging device for the lumberjack gem that writes log entries as JSON documentspec."
  spec.homepage = "https://github.com/bdurand/lumberjack_json_device"
  spec.license = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  ignore_files = %w(
    .gitignore
    .travis.yml
    Appraisals
    Gemfile
    Gemfile.lock
    Rakefile
    gemfiles/
    spec/
  )
  spec.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject{ |f| ignore_files.any?{ |path| f.start_with?(path) } }
  end

  spec.require_paths = ['lib']

  spec.add_dependency "lumberjack", ">=2.0"
  spec.add_dependency "multi_json"

  spec.add_development_dependency("rspec", ["~> 3.0"])
  spec.add_development_dependency "rake"
end
