# frozen_string_literal: true

require 'active_model'
require 'active_support/core_ext/array/wrap'
require 'active_support/core_ext/object/try'

module CouchbaseOrm
    module N1ql
        extend ActiveSupport::Concern
        NO_VALUE = :no_value_specified
        DEFAULT_SCAN_CONSISTENCY = :request_plus
        # sanitize for injection query
        def self.sanitize(value)
            if value.is_a?(String)
                value.gsub("'", "''").gsub("\\"){"\\\\"}.gsub('"', '\"')
            elsif value.is_a?(Array)
                value.map{ |v| sanitize(v) }
            else
                value
            end
        end

        def self.config(new_config = nil)
            Thread.current['__couchbaseorm_n1ql_config__'] = new_config if new_config
            Thread.current['__couchbaseorm_n1ql_config__'] || {
                scan_consistency: DEFAULT_SCAN_CONSISTENCY
            }
        end

        module ClassMethods
            # Defines a query N1QL for the model
            #
            # @param [Symbol, String, Array] names names of the views
            # @param [Hash] options options passed to the {Couchbase::N1QL}
            #
            # @example Define some N1QL queries for a model
            #  class Post < CouchbaseOrm::Base
            #    n1ql :by_rating, emit_key: :rating
            #  end
            #
            #  Post.by_rating do |response|
            #    # ...
            #  end
            # TODO: add range keys [:startkey, :endkey]
            def n1ql(name, query_fn: nil, emit_key: [], custom_order: nil, **options)
                raise ArgumentError, "#{self} already respond_to? #{name}" if self.respond_to?(name)

                emit_key = Array.wrap(emit_key)
                emit_key.each do |key|
                    raise "unknown emit_key attribute for n1ql :#{name}, emit_key: :#{key}" if key && !attribute_names.include?(key.to_s)
                end
                options = N1QL_DEFAULTS.merge(options)
                method_opts = {}
                method_opts[:emit_key] = emit_key

                @indexes ||= {}
                @indexes[name] = method_opts

                singleton_class.__send__(:define_method, name) do |key: NO_VALUE, **opts, &result_modifier|
                    opts = options.merge(opts).reverse_merge(scan_consistency: CouchbaseOrm::N1ql.config[:scan_consistency])
                    values = key == NO_VALUE ? NO_VALUE : convert_values(method_opts[:emit_key], key)
                    current_query = run_query(method_opts[:emit_key], values, query_fn, custom_order: custom_order, **opts.except(:include_docs, :key))
                    if result_modifier
                        opts[:include_docs] = true
                        current_query.results &result_modifier
                    elsif opts[:include_docs]
                        current_query.results { |res| find(res) }
                    else
                        current_query.results
                    end
                end
            end
            N1QL_DEFAULTS = { include_docs: true }

            # add a n1ql query and lookup method to the model for finding all records
            # using a value in the supplied attr.
            def index_n1ql(attr, validate: true, find_method: nil, n1ql_method: nil)
                n1ql_method ||= "by_#{attr}"
                find_method ||= "find_#{n1ql_method}"

                validates(attr, presence: true) if validate
                n1ql n1ql_method, emit_key: attr

                define_singleton_method find_method do |value|
                    send n1ql_method, key: [value]
                end
            end

            private

            def convert_values(keys, values)
                return values if keys.empty? && Array.wrap(values).any?
                keys.zip(Array.wrap(values)).map do |key, value_before_type_cast|
                    serialize_value(key, value_before_type_cast)
                end
            end

            def build_where(keys, values)
                where = values == NO_VALUE ? '' : keys.zip(Array.wrap(values))
                            .reject { |key, value| key.nil? && value.nil? }
                            .map { |key, value| build_match(key, value) }
                            .join(" AND ")
                "type=\"#{design_document}\" #{"AND " + where unless where.blank?}"
            end

            # order-by-clause ::= ORDER BY ordering-term [ ',' ordering-term ]*
            # ordering-term ::= expr [ ASC | DESC ] [ NULLS ( FIRST | LAST ) ]
            # see https://docs.couchbase.com/server/5.0/n1ql/n1ql-language-reference/orderby.html
            def build_order(keys, descending)
                "#{keys.dup.push("meta().id").map { |k| "#{k} #{descending ? "desc" : "asc" }" }.join(",")}"
            end

            def build_limit(limit)
                limit ? "limit #{limit}" : ""
            end

            def run_query(keys, values, query_fn, custom_order: nil, descending: false, limit: nil, **options)
                if query_fn
                    N1qlProxy.new(query_fn.call(bucket, values, Couchbase::Options::Query.new(**options)))
                else
                    bucket_name = bucket.name
                    where = build_where(keys, values)
                    order = custom_order || build_order(keys, descending)
                    limit = build_limit(limit)
                    n1ql_query = "select raw meta().id from `#{bucket_name}` where #{where} order by #{order} #{limit}"
                    result = cluster.query(n1ql_query, Couchbase::Options::Query.new(**options))
                    CouchbaseOrm.logger.debug  "N1QL query: #{n1ql_query} return #{result.rows.to_a.length} rows with scan_consistency : #{options[:scan_consistency]}"
                    N1qlProxy.new(result)
                end
            end
        end
    end
end
