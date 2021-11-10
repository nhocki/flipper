require 'set'
require 'flipper'
require 'active_record'

module Flipper
  module Adapters
    class ActiveRecord
      include ::Flipper::Adapter

      # Private: Do not use outside of this adapter.
      class Feature < ::ActiveRecord::Base
        self.table_name = [
          ::ActiveRecord::Base.table_name_prefix,
          "flipper_features",
          ::ActiveRecord::Base.table_name_suffix,
        ].join

        has_many :gates, foreign_key: "feature_key", primary_key: "key"
      end

      # Private: Do not use outside of this adapter.
      class Gate < ::ActiveRecord::Base
        self.table_name = [
          ::ActiveRecord::Base.table_name_prefix,
          "flipper_gates",
          ::ActiveRecord::Base.table_name_suffix,
        ].join
      end

      VALUE_TO_TEXT_WARNING = <<-EOS
        Your database needs migrated to use the latest Flipper features.
        See https://github.com/jnunemaker/flipper/issues/557
      EOS

      # Public: The name of the adapter.
      attr_reader :name

      # Public: Initialize a new ActiveRecord adapter instance.
      #
      # name - The Symbol name for this adapter. Optional (default :active_record)
      # feature_class - The AR class responsible for the features table.
      # gate_class - The AR class responsible for the gates table.
      #
      # Allowing the overriding of name is so you can differentiate multiple
      # instances of this adapter from each other, if, for some reason, that is
      # a thing you do.
      #
      # Allowing the overriding of the default feature/gate classes means you
      # can roll your own tables and what not, if you so desire.
      def initialize(options = {})
        @name = options.fetch(:name, :active_record)
        @feature_class = options.fetch(:feature_class) { Feature }
        @gate_class = options.fetch(:gate_class) { Gate }

        warn VALUE_TO_TEXT_WARNING if value_not_text?
      end

      # Public: The set of known features.
      def features
        @feature_class.all.map(&:key).to_set
      end

      # Public: Adds a feature to the set of known features.
      def add(feature)
        # race condition, but add is only used by enable/disable which happen
        # super rarely, so it shouldn't matter in practice
        @feature_class.transaction do
          unless @feature_class.where(key: feature.key).first
            begin
              @feature_class.create! { |f| f.key = feature.key }
            rescue ::ActiveRecord::RecordNotUnique
            end
          end
        end

        true
      end

      # Public: Removes a feature from the set of known features.
      def remove(feature)
        @feature_class.transaction do
          @feature_class.where(key: feature.key).destroy_all
          clear(feature)
        end
        true
      end

      # Public: Clears the gate values for a feature.
      def clear(feature)
        @gate_class.where(feature_key: feature.key).destroy_all
        true
      end

      # Public: Gets the values for all gates for a given feature.
      #
      # Returns a Hash of Flipper::Gate#key => value.
      def get(feature)
        db_gates = @gate_class.where(feature_key: feature.key)
        result_for_feature(feature, db_gates)
      end

      def get_multi(features)
        db_gates = @gate_class.where(feature_key: features.map(&:key))
        grouped_db_gates = db_gates.group_by(&:feature_key)
        result = {}
        features.each do |feature|
          result[feature.key] = result_for_feature(feature, grouped_db_gates[feature.key])
        end
        result
      end

      def get_all
        result = Hash.new { |hash, key| hash[key] = default_config }

        @feature_class.includes(:gates).all.each do |f|
          feature = Flipper::Feature.new(f.key, self)
          result[feature.key] = result_for_feature(feature, f.gates)
        end

        result
      end

      # Public: Enables a gate for a given thing.
      #
      # feature - The Flipper::Feature for the gate.
      # gate - The Flipper::Gate to enable.
      # thing - The Flipper::Type being enabled for the gate.
      #
      # Returns true.
      def enable(feature, gate, thing)
        case gate.data_type
        when :boolean
          set(feature, gate, thing, clear: true)
        when :integer
          set(feature, gate, thing)
        when :json
          set(feature, gate, thing, json: true)
        when :set
          enable_multi(feature, gate, thing)
        else
          unsupported_data_type gate.data_type
        end

        true
      end

      # Public: Disables a gate for a given thing.
      #
      # feature - The Flipper::Feature for the gate.
      # gate - The Flipper::Gate to disable.
      # thing - The Flipper::Type being disabled for the gate.
      #
      # Returns true.
      def disable(feature, gate, thing)
        case gate.data_type
        when :boolean
          clear(feature)
        when :integer
          set(feature, gate, thing)
        when :json
          delete(feature, gate)
        when :set
          @gate_class.where(feature_key: feature.key, key: gate.key, value: thing.value).destroy_all
        else
          unsupported_data_type gate.data_type
        end

        true
      end

      # Private
      def unsupported_data_type(data_type)
        raise "#{data_type} is not supported by this adapter"
      end

      private

      def set(feature, gate, thing, options = {})
        clear_feature = options.fetch(:clear, false)
        json_feature = options.fetch(:json, false)

        raise VALUE_TO_TEXT_WARNING if json_feature && value_not_text?

        @gate_class.transaction do
          clear(feature) if clear_feature
          delete(feature, gate)
          begin
            @gate_class.create! do |g|
              g.feature_key = feature.key
              g.key = gate.key
              g.value = json_feature ? JSON.dump(thing.value) : thing.value.to_s
            end
          rescue ::ActiveRecord::RecordNotUnique
            # assume this happened concurrently with the same thing and its fine
            # see https://github.com/jnunemaker/flipper/issues/544
          end
        end

        nil
      end

      def delete(feature, gate)
        @gate_class.where(feature_key: feature.key, key: gate.key).destroy_all
      end

      def enable_multi(feature, gate, thing)
        @gate_class.create! do |g|
          g.feature_key = feature.key
          g.key = gate.key
          g.value = thing.value
        end

        nil
      rescue ::ActiveRecord::RecordNotUnique
        # already added so no need move on with life
      end

      def result_for_feature(feature, db_gates)
        db_gates ||= []
        result = {}
        feature.gates.each do |gate|
          result[gate.key] =
            case gate.data_type
            when :boolean, :integer
              if detected_db_gate = db_gates.detect { |db_gate| db_gate.key == gate.key.to_s }
                detected_db_gate.value
              end
            when :json
              if detected_db_gate = db_gates.detect { |db_gate| db_gate.key == gate.key.to_s }
                JSON.parse(detected_db_gate.value)
              end
            when :set
              db_gates.select { |db_gate| db_gate.key == gate.key.to_s }.map(&:value).to_set
            else
              unsupported_data_type gate.data_type
            end
        end
        result
      end

      # Check if value column is text instead of string
      # See TODO:link/to/PR
      def value_not_text?
        @gate_class.column_for_attribute(:value).type != :text
      end
    end
  end
end

Flipper.configure do |config|
  config.adapter { Flipper::Adapters::ActiveRecord.new }
end
