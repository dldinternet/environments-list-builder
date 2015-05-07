require 'cicd/builder/manifest'

module CiCd
  module Builder
    _lib=File.dirname(__FILE__)
    $:.unshift(_lib) unless $:.include?(_lib)

    require 'cicd/builder/environments-list/version'

    module EnvironmentsList
      class Runner < Manifest::Runner
        require 'cicd/builder/environments-list/mixlib/build'
        include CiCd::Builder::EnvironmentsList::Build
        require 'cicd/builder/environments-list/mixlib/repo'
        include CiCd::Builder::EnvironmentsList::Repo

        # ---------------------------------------------------------------------------------------------------------------
        def initialize()
          super
          @klass = 'CiCd::Builder::EnvironmentsList'
          @default_options[:builder] = VERSION
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getBuilderVersion
          {
              version:  VERSION,
              major:    MAJOR,
              minor:    MINOR,
              patch:    PATCH,
          }
        end

        # ---------------------------------------------------------------------------------------------------------------
        def checkEnvironment()
          @logger.step CLASS+'::'+__method__.to_s
          # We fake some of the keys that the will need later ...
          fakes = @default_options[:env_keys].select{|key| key =~ /^(CLASSES|REPO_PRODUCTS|MANIFEST_FILE)/}
          faked = {}
          fakes.each do |key|
            unless ENV.has_key?(key)
              ENV[key]='faked'
              faked[key] = true
            end
          end
          ret = super
          faked.each do |k,_|
            ENV.delete k
            @default_options[:env_unused].delete k if @default_options[:env_unused]
          end
          @default_options[:env_unused] = @default_options[:env_unused].select{|k| k !~ /^(ARTIFACTORY|AWS_INI)/} if @default_options[:env_unused]
          ret
        end

        # ---------------------------------------------------------------------------------------------------------------
        def setup()
          $stdout.write("EnvironmentsListBuilder v#{CiCd::Builder::EnvironmentsList::VERSION}\n")
          @default_options[:env_keys] << %w(
                                            ARTIFACTORY_RELEASE_REPO
                                            ARTIFACTORY_ENVIRONMENTS_MODULE
                                           )
          super
        end

      end
    end

  end
end
