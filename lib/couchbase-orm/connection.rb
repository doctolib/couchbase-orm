
require 'couchbase'

module CouchbaseOrm
    class Connection
        def self.cluster
            @cluster ||= begin
                options = Couchbase::Cluster::ClusterOptions.new
                options.authenticate(ENV["COUCHBASE_USER"], ENV["COUCHBASE_PASSWORD"])
                Couchbase::Cluster.connect(ENV["COUCHBASE_CONNECTION_STRING"], options)
            end
        end

        def self.bucket
            @bucket ||= cluster.bucket(ENV['COUCHBASE_BUCKET'])
        end
    end
end
