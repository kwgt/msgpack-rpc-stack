
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "msgpack/rpc/version"

Gem::Specification.new do |spec|
  spec.name          = "msgpack-rpc-stack"
  spec.version       = MessagePack::Rpc::VERSION
  spec.authors       = ["Hiroshi Kuwagata"]
  spec.email         = ["kgt9221@gmail.com"]

  spec.summary       = %q{MessagePack-RPC module}
  spec.description   = %q{A module of implementation MessagePack-RPC stack}
  spec.homepage      = "https://github.com/kwgt/msgpack-rpc-stack"
  spec.license       = "MIT"

  if spec.respond_to?(:metadata)
    spec.metadata["homepage_uri"] = spec.homepage
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
          "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    (`git ls-files -z`).split("\x0").reject { |f|
      f.match(%r{^(test|spec|features)/})
    }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.4.0"

  spec.add_development_dependency "bundler", ">= 2.1"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_dependency "msgpack", ">= 1.6.0"
end
