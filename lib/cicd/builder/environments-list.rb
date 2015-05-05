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
        def setup()
          $stdout.write("EnvironmentsListBuilder v#{CiCd::Builder::EnvironmentsList::VERSION}\n")
          @default_options[:env_keys] << %w(
                                            REPO_PRODUCTS
                                            ARTIFACTORY_RELEASE_REPO
                                            ARTIFACTORY_ENVIRONMENTS_MODULE
                                           )
          @default_options[:env_keys] = @default_options[:env_keys].select{|key| key !~ /^CLASSES/}
          super
        end

      end
    end

  end
end
