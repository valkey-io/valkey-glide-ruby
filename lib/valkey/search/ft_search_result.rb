# frozen_string_literal: true

class Valkey
  module Search
    # A single document from an FT.SEARCH result.
    #
    # @example
    #   doc = result.documents.first
    #   doc.key         # => "doc:1"
    #   doc.fields      # => {"title" => "hello", "price" => "9.99"}
    #   doc["title"]    # => "hello"
    #   doc.sort_key    # => "9.99" (only with WITHSORTKEYS)
    #
    class FtSearchDocument
      # @return [String] the document key
      attr_reader :key

      # @return [Hash<String, String>] field name/value pairs
      attr_reader :fields

      # @return [String, nil] sort key value (present only when WITHSORTKEYS is used)
      attr_reader :sort_key

      # @param key [String] document key
      # @param fields [Hash<String, String>] document fields
      # @param sort_key [String, nil] sort key value
      def initialize(key, fields, sort_key: nil)
        @key = key
        @fields = fields
        @sort_key = sort_key
      end

      # Shorthand for accessing a field value.
      #
      # @param field_name [String] field name
      # @return [String, nil]
      def [](field_name)
        @fields[field_name]
      end

      # @return [String]
      def to_s
        "#<FtSearchDocument key=#{@key.inspect} fields=#{@fields.inspect}>"
      end

      alias inspect to_s
    end

    # Structured result from an FT.SEARCH command.
    #
    # Wraps the raw response array from glide-core into a typed object
    # with total result count and an array of {FtSearchDocument} objects.
    #
    # @example
    #   result = client.ft_search("idx", "@title:hello", options: opts)
    #   result.total_results   # => 2
    #   result.documents       # => [FtSearchDocument, ...]
    #   result.documents.first.key    # => "doc:1"
    #   result.documents.first["title"]  # => "hello world"
    #
    class FtSearchResult
      # @return [Integer] total number of matching documents
      attr_reader :total_results

      # @return [Array<FtSearchDocument>] documents in this page
      attr_reader :documents

      # @param total_results [Integer] total matching document count
      # @param documents [Array<FtSearchDocument>] parsed documents
      def initialize(total_results, documents)
        @total_results = total_results
        @documents = documents
      end

      # Parse a raw FT.SEARCH response from glide-core.
      #
      # glide-core normalizes FT.SEARCH responses into:
      #   [count, {key => fields_hash, ...}]
      #
      # When WITHSORTKEYS is enabled, each document value becomes:
      #   [sort_key, fields_hash]
      #
      # @param raw [Array] raw response from glide-core
      # @param withsortkeys [Boolean] whether WITHSORTKEYS was used
      # @return [FtSearchResult]
      def self.from_raw(raw, withsortkeys: false)
        return new(0, []) if raw.nil? || raw.empty?

        count = raw[0].is_a?(Integer) ? raw[0] : raw[0].to_i
        documents = []

        if raw.length > 1 && raw[1].is_a?(Hash)
          raw[1].each do |key, value|
            doc_key = key.to_s
            if withsortkeys && value.is_a?(Array) && value.length == 2
              sort_key = value[0]&.to_s
              field_map = normalize_fields(value[1])
              documents << FtSearchDocument.new(doc_key, field_map, sort_key: sort_key)
            else
              field_map = normalize_fields(value)
              documents << FtSearchDocument.new(doc_key, field_map)
            end
          end
        end

        new(count, documents)
      end

      # @return [String]
      def to_s
        "#<FtSearchResult total=#{@total_results} docs=#{@documents.size}>"
      end

      alias inspect to_s

      class << self
        private

        # Normalize field values to a string hash.
        # Handles both Hash input and Array (key-value pairs) input.
        #
        # @param fields [Hash, Array, nil]
        # @return [Hash<String, String>]
        def normalize_fields(fields)
          case fields
          when Hash
            fields.each_with_object({}) do |(k, v), h|
              h[k.to_s] = v.to_s
            end
          when Array
            # Array of alternating [key, val, key, val, ...]
            result = {}
            fields.each_slice(2) { |k, v| result[k.to_s] = v.to_s }
            result
          else
            {}
          end
        end
      end
    end
  end
end
