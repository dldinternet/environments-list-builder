# -*- encoding: utf-8 -*-

require File.expand_path('../lib/cicd/builder/environments-list/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'environments-list-builder'
  gem.version       = CiCd::Builder::EnvironmentsList::VERSION
  gem.summary       = %q{Jenkins builder task for CI/CD}
  gem.description   = %q{Jenkins builder of the environments manifest for Continuous Integration/Continuous Delivery artifact promotion style deployments}
  gem.license       = "Apachev2"
  gem.authors       = ["Christo De Lange"]
  gem.email         = "rubygems@dldinternet.com"
  gem.homepage      = "https://rubygems.org/gems/environments-list-builder"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ['lib']

  gem.add_dependency 'manifest-builder', '>= 0.7.0', '< 1.1'
  gem.add_dependency 'json', '>= 1.8.1', '< 1.9'
  gem.add_dependency 's3etag', '>= 0.0.1', '< 0.1.0'
  gem.add_dependency 'archive-tar-minitar', '= 0.5.2'
  gem.add_dependency 'hashie', '>= 2.1.2', '< 3.5'
  gem.add_dependency 'awesome_print'
  gem.add_dependency 'colorize'
  gem.add_dependency 'inifile'
  gem.add_dependency 'thor'
  gem.add_dependency 'aws-sdk', '>= 2.0', '< 2.1'
  gem.add_dependency 'dldinternet-mixlib-logging'

  gem.add_development_dependency 'bundler', '>= 1.7', '< 2.0'
  gem.add_development_dependency 'rake', '>= 10.3', '< 11'
  gem.add_development_dependency 'rubygems-tasks', '>= 0.2', '< 1.1'
  gem.add_development_dependency 'cucumber', '>= 0.10.7', '< 0.11'
  gem.add_development_dependency 'rspec', '>= 2.99', '< 3.0'
end
