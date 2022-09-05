
require 'couchbase'

module CouchbaseOrm
    class Connection
        def self.cluster(config = nil)
            # use the config loaded by couchbase gem railtie from config/couchbase.yml
            config ||= Rails.configuration.couchbase if defined?(::Rails)
            raise 'Missing Couchbase configuration' unless config

            @cluster ||= Couchbase::Cluster.connect(config)
        end

        def self.bucket(name = nil)
            # use the bucket name from config/couchbase.yml
            name ||= Rails.application.config_for(:couchbase).bucket if defined?(::Rails)
            raise 'Missing bucket name' unless name

            @bucket ||= cluster.bucket(name)
        end
    end
end
