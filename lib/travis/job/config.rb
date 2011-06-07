module Travis
  module Job
    # Build configuration job: read .travis.yml and return it
    class Config < Base
      protected

        def perform
          { :config => read }
        end

        def finish(data)
          notify(:finish, data)
        end

        # TODO instead we could just do an http request to the github raw file here
        def read
          chdir do
            repository.checkout(build.commit)
            YAML.load(File.read('.travis.yml')) || {}
          end
        rescue Errno::ENOENT => e
          {}
        end
    end
  end
end