# frozen_string_literal: true
# rubocop:todo all

module CouchbaseOrm
  module Timestamps
    # This module handles the behavior for setting up document created at
    # timestamp.
    module Created
      extend ActiveSupport::Concern

      included do
        set_callback :create, :before, :set_created_at, if: -> { attributes.has_key? 'created_at' }
      end

      # Update the created_at attribute on the Document to the current time. This is
      # only called on create.
      #
      # @example Set the created at time.
      #   person.set_created_at
      def set_created_at
        return if created_at

        time = Time.current
        self.updated_at = time if is_a?(Updated) && !updated_at_changed?
        self.created_at = time
      end
    end
  end
end