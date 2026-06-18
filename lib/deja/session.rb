# frozen_string_literal: true

module Deja
  # The per-example runtime. Installs every registered adapter's caching stub (so
  # a suite can mix providers — each test exercises whichever it actually calls),
  # and aggregates the captured calls across adapters.
  module Session
    module_function

    # Install all registered adapters' stubs and reset the captured call log.
    def enable
      Deja.reset_calls!
      adapters = Deja.adapters
      if adapters.empty?
        raise Deja::Error, "No providers registered. Call `c.register :anthropic, ...` inside Deja.configure."
      end

      adapters.each {|adapter| install(adapter, adapter.build_mock_client) }
    end

    # Install a poison client for every adapter so any LLM access raises.
    def forbid
      Deja.adapters.each {|adapter| install(adapter, poison_client) }
    end

    # Runs an adapter's install block in the current example's context (so RSpec's
    # `allow` is available), handing it the client to return.
    def install(adapter, client)
      example_instance!.instance_exec(client, &adapter.install_block)
    end

    # Assert exactly one call was captured across all adapters; return its kwargs.
    def expect_called
      instance = example_instance!
      instance.instance_exec do
        expect(Deja.calls.size).to eq(1)
      end
      Deja.calls.first[:kwargs]
    end

    def example_instance!
      RSpec.current_example&.example_group_instance or
        raise Deja::Error, "Deja must be used inside an RSpec example"
    end

    def poison_client
      poison = Object.new
      def poison.method_missing(*) = raise("LLM should not be called (deja forbid_llm_calls)")
      def poison.respond_to_missing?(*) = true
      poison
    end
  end
end
