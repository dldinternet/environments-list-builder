require 'artifactory'
require 'tmpdir'
require "cicd/builder/manifest/mixlib/repo/artifactory"

module CiCd
  module Builder
    # noinspection RubySuperCallWithoutSuperclassInspection
    module EnvironmentsList
      module Repo
        class Artifactory < CiCd::Builder::Manifest::Repo::Artifactory

          alias_method :super_uploadToRepo, :uploadToRepo
          # ---------------------------------------------------------------------------------------------------------------
          def uploadToRepo(artifacts)
            @logger.step CLASS+'::'+__method__.to_s
            # super_uploadToRepo(artifacts) get's the immediate parent class
            cicd_uploadToRepo(artifacts)
            # CiCd::Builder::Repo::Artifactory.instance_method(:uploadToRepo).bind(self).call(artifacts)
            if @vars[:environments][:changed]
              data = {
                         name: ENV['ARTIFACTORY_ENVIRONMENTS_MODULE'],
                       module: ENV['ARTIFACTORY_ENVIRONMENTS_MODULE'],
                         file: @vars[:environments][:file],
                      version: @vars[:environments][:version],
                        build: @vars[:build_num],
                   properties: @properties_matrix,
                         temp: false,
                         sha1: Digest::SHA1.file(@vars[:environments][:file]).hexdigest,
                          md5: Digest::MD5.file(@vars[:environments][:file]).hexdigest,
              }

              cicd_maybeUploadArtifactoryObject(
                              data: data,
                   artifact_module: data[:module],
                  artifact_version: data[:version],
                         file_name: '',
                          file_ext: File.extname(data[:file]).gsub(/^\./,''),
                              repo: ENV['ARTIFACTORY_RELEASE_REPO'],
                              copy: false
              )
            end
            @vars[:return_code]
          end

        end
      end
    end
  end
end
