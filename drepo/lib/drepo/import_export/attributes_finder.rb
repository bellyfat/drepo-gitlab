# frozen_string_literal: true

module Drepo
  module ImportExport
    class AttributesFinder
      def initialize(included_attributes:, excluded_attributes:, methods:, diffs:, inline_associations:)
        @included_attributes = included_attributes || {}
        @excluded_attributes = excluded_attributes || {}
        @methods = methods || {}
        @diffs = diffs || {}
        @inline_associations = inline_associations || {}
      end

      def find(model_object)
        parsed_hash = find_attributes_only(model_object)
        parsed_hash.empty? ? model_object : { model_object => parsed_hash }
      end

      def parse(model_object)
        parsed_hash = find_attributes_only(model_object)
        yield parsed_hash unless parsed_hash.empty?
      end

      def find_included(value)
        key = key_from_hash(value)
        @included_attributes[key].nil? ? {} : { only: @included_attributes[key] }
      end

      def find_excluded(value)
        key = key_from_hash(value)
        @excluded_attributes[key].nil? ? {} : { except: @excluded_attributes[key] }
      end

      def find_method(value)
        key = key_from_hash(value)
        @methods[key].nil? ? {} : { methods: @methods[key] }
      end

      def find_diff(value)
        key = key_from_hash(value)
        @diffs.include?(key) ? { diffs: true } : {}
      end

      def find_inline(value)
        key = key_from_hash(value)
        @inline_associations.include?(key) ? { inline: true } : {}
      end

      def find_excluded_keys(klass_name)
        @excluded_attributes[klass_name.to_sym]&.map(&:to_s) || []
      end

      private

      def find_attributes_only(value)
        find_included(value).merge(find_excluded(value)).merge(find_method(value)).merge(find_diff(value)).merge(find_inline(value))
      end

      def key_from_hash(value)
        value.is_a?(Hash) ? value.keys.first : value
      end
    end
  end
end