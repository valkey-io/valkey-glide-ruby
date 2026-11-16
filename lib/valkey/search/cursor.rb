# frozen_string_literal: true

class Valkey
  module Search
    # A single entry in FT.AGGREGATE/FT.HYBRID's LOAD clause, optionally
    # renaming the loaded field via AS. Mirrors Python's LoadField.
    #
    # `AS <alias>` in the LOAD clause is a compatibility fix introduced in
    # valkey-search 1.3.0 (`ft_aggregate_load_as`, see COMPATIBILITY.md).
    # Below `search.emulate-release 1.3.0` the legacy parser does not
    # recognize AS as a rename keyword: it is consumed as just another LOAD
    # field token, and the server then rejects the command with
    # "Index: field `AS` does not exist". This class does not guard against
    # that client-side; it requires `search.emulate-release` >= 1.3.0 to
    # behave as documented.
    #
    # @example
    #   Valkey::Search::LoadField.new("price", alias: "p")
    class LoadField
      # @return [String] the field identifier to load
      attr_reader :field_identifier
      # @return [String, nil] optional AS alias
      attr_reader :alias_name

      # @param field_identifier [String] the field to load
      # @param alias [String, nil] emit `AS <alias>` after the field
      def initialize(field_identifier, alias: nil)
        @field_identifier = field_identifier
        @alias_name = binding.local_variable_get(:alias)
      end

      # @return [Array] `<field_identifier> [AS <alias>]`
      def to_args
        @alias_name.nil? ? [@field_identifier] : [@field_identifier, "AS", @alias_name]
      end
    end

    # Serialize a LOAD clause's field list for FT.AGGREGATE and FT.HYBRID
    # (shared — the two commands' LOAD clause grammar is byte-identical).
    #
    # The emitted count is a *token* budget, not an entry count: a
    # {LoadField} with an alias contributes 3 tokens (field, AS, alias)
    # rather than 1, matching the server's own accounting.
    #
    # @param load_fields [Array<String, LoadField>, nil]
    # @return [Array] `LOAD <n> <field...>`, or [] when empty/nil
    def self.load_fields_to_args(load_fields)
      return [] if load_fields.nil? || load_fields.empty?

      tokens = load_fields.flat_map { |entry| entry.is_a?(LoadField) ? entry.to_args : [entry] }
      ["LOAD", tokens.length, *tokens]
    end

    # Serialize a PARAMS option, shared between FT.AGGREGATE and FT.HYBRID.
    # `params_keyword` lets a caller pass its own command-specific keyword
    # constant even though both currently serialize to the same literal text.
    #
    # @param params [Hash, nil]
    # @param params_keyword [String] the keyword token ("PARAMS")
    # @return [Array] `<params_keyword> <n> <k> <v>...`, or [] when empty/nil
    def self.params_to_args(params, params_keyword: "PARAMS")
      return [] if params.nil? || params.empty?

      flat = params.flat_map { |k, v| [k.to_s, v] }
      [params_keyword, flat.length, *flat]
    end

    # The WITHCURSOR option, requesting a paged reply instead of the whole
    # result set at once. Shared verbatim between FT.AGGREGATE and FT.HYBRID
    # — both commands drive the exact same aggregate-suffix parser, so the
    # grammar (`WITHCURSOR [COUNT n] [MAXIDLE ms]`) and reply shape are
    # identical regardless of which command opened the cursor.
    #
    # A paged query, and every subsequent {Valkey::Commands::VectorSearchCommands#ft_cursor_read}/
    # {Valkey::Commands::VectorSearchCommands#ft_cursor_del} against the cursor it opens, is
    # pinned to the PRIMARY of the index's own slot regardless of ReadFrom — a
    # cursor is a per-process, node-local server resource, and this is a
    # deliberate, documented exception to GLIDE's normal read routing.
    #
    # @example
    #   Valkey::Search::WithCursor.new(count: 10, maxidle: 5000)
    class WithCursor
      # @param count [Integer, nil] rows to return per page
      # @param maxidle [Integer, nil] idle timeout in milliseconds before the
      #   server discards the cursor
      def initialize(count: nil, maxidle: nil)
        @count = count
        @maxidle = maxidle
      end

      # @return [Array] `WITHCURSOR [COUNT <n>] [MAXIDLE <ms>]`
      def to_args
        args = ["WITHCURSOR"]
        args.push("COUNT", @count) unless @count.nil?
        args.push("MAXIDLE", @maxidle) unless @maxidle.nil?
        args
      end
    end
  end
end
