# frozen_string_literal: true

require "pathname"
require_relative "slice"

module Hanami
  # Base class for gem-defined slices.
  #
  # Inherits from `Hanami::Slice`, so subclasses are full-fledged slices.
  # The only addition over `Hanami::Slice` is that `config.root` is inferred
  # from the file where the subclass is defined, so external-slice gem
  # authors don't need to set it manually.
  #
  # @example In a gem at `sysinfo/lib/sysinfo/slice.rb`
  #   require "hanami/external_slice"
  #
  #   module Sysinfo
  #     class Slice < Hanami::ExternalSlice
  #       # config.root is now Pathname("sysinfo/lib/sysinfo")
  #     end
  #   end
  #
  # If `config.root` is already set before this hook runs, the existing value
  # is preserved (escape hatch for unusual gem layouts).
  #
  # @since 3.0.0
  # @api public
  class ExternalSlice < Slice
    def self.inherited(subclass)
      super

      caller_path = caller_locations(1, 1).first.path
      subclass.config.root ||= Pathname(File.dirname(caller_path))
    end
  end
end
