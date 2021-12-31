# frozen_string_literal: true

module Fourier
  module Services
    module Generate
      class Tuist < Base
        attr_reader :open
        attr_reader :targets

        def initialize(open: false, targets: [])
          @open = open
          @targets = targets
        end

        def call
          dependencies = ["dependencies", "fetch"]
          Utilities::System.tuist(*dependencies)

          cache_warm = ["cache", "warm", "--dependencies-only"] + targets
          Utilities::System.tuist(*cache_warm)

          generate = ["generate"] + targets
          generate << "--open" if open
          Utilities::System.tuist(*generate)
        end
      end
    end
  end
end
