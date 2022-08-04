
require 'couchbase'

module CouchbaseOrm
    class Connection
        def self.cluster
            @cluster ||= Couchbase::Cluster.connect(Rails.application.config.couchbase)
        end

        def self.bucket
            @bucket ||= cluster.bucket(Rails.application.config.couchbase_orm.bucket)
        end
    end
end
