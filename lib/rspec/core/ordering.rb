module RSpec
  module Core
    if defined?(::Random)
      RandomNumberGenerator = ::Random
    else
      require 'rspec/core/backport_random'
      RandomNumberGenerator = RSpec::Core::Backports::Random
    end

    # @private
    module Ordering
      # @private
      # The default global ordering (defined order).
      class Identity
        def order(items)
          items
        end
      end

      # @private
      # Orders items randomly.
      class Random
        def initialize(configuration)
          @configuration = configuration
          @used = false
        end

        def used?
          @used
        end

        def order(items)
          @used = true
          rng = RandomNumberGenerator.new(@configuration.seed)
          shuffle items, rng
        end

        if RUBY_VERSION > '1.9.3'
          def shuffle(list, rng)
            list.shuffle(:random => rng)
          end
        else
          def shuffle(list, rng)
            shuffled = list.dup
            shuffled.size.times do |i|
              j = i + rng.rand(shuffled.size - i)
              next if i == j
              shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end

            shuffled
          end
        end
      end

      # @private
      # Orders items based on a custom block.
      class Custom
        def initialize(callable)
          @callable = callable
        end

        def order(list)
          @callable.call(list)
        end
      end

      # @private
      # Stores the different ordering strategies.
      class Registry
        def initialize(configuration)
          @configuration = configuration
          @strategies    = {}

          register(:random,  Random.new(configuration))

          identity = Identity.new
          register(:defined, identity)

          # The default global ordering is --defined.
          register(:global, identity)
        end

        def fetch(name, &fallback)
          @strategies.fetch(name, &fallback)
        end

        def register(sym, strategy)
          @strategies[sym] = strategy
        end

        def used_random_seed?
          @strategies[:random].used?
        end
      end

      # @private
      # Manages ordering configuration.
      #
      # @note This is not intended to be used externally. Use
      #       the APIs provided by `RSpec::Core::Configuration` instead.
      class ConfigurationManager
        attr_reader :seed, :ordering_registry

        def initialize
          @ordering_registry = Registry.new(self)
          @seed = rand(0xFFFF)
          @seed_forced = false
          @order_forced = false
        end

        def seed_used?
          ordering_registry.used_random_seed?
        end

        def seed=(seed)
          return if @seed_forced
          register_ordering(:global, ordering_registry.fetch(:random))
          @seed = seed.to_i
        end

        def order=(type)
          order, seed = type.to_s.split(':')
          @seed = seed = seed.to_i if seed

          ordering_name = if order.include?('rand')
            :random
          elsif order == 'defined'
            :defined
          end

          register_ordering(:global, ordering_registry.fetch(ordering_name)) if ordering_name
        end

        def force(hash)
          if hash.has_key?(:seed)
            self.seed = hash[:seed]
            @seed_forced  = true
            @order_forced = true
          elsif hash.has_key?(:order)
            self.order = hash[:order]
            @order_forced = true
          end
        end

        def register_ordering(name, strategy = Custom.new(Proc.new { |l| yield l }))
          return if @order_forced && name == :global
          ordering_registry.register(name, strategy)
        end
      end
    end
  end
end

