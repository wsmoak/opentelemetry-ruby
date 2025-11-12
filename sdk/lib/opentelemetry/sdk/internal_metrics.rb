# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module SDK
    # Internal metrics module for tracking SDK component state
    module InternalMetrics
      @mutex = Mutex.new
      @instance_counters = {}
      @pid = nil

      class << self
        # Register a processor instance and return its unique name
        #
        # @param [String] component_type The type of component (e.g., 'batching_log_record_processor')
        # @return [String] Unique component name (e.g., 'batching_log_record_processor/0')
        def register_processor_instance(component_type)
          @mutex.synchronize do
            reset_on_fork

            @instance_counters[component_type] ||= 0
            counter = @instance_counters[component_type]
            @instance_counters[component_type] += 1

            "#{component_type}/#{counter}"
          end
        end

        # Get the global meter provider (if available)
        #
        # @return [OpenTelemetry::SDK::Metrics::MeterProvider, nil]
        def meter_provider
          # Try to get the global meter provider
          OpenTelemetry.meter_provider
        rescue StandardError
          nil
        end

        # Create a meter for SDK internal metrics
        #
        # @return [OpenTelemetry::Metrics::Meter, nil]
        def meter
          return nil unless meter_provider

          @meter ||= meter_provider.meter(
            'opentelemetry-sdk'
                  )
                       end

        private

        def reset_on_fork
          pid = Process.pid
          return if @pid == pid

          @pid = pid
          @instance_counters.clear
        end
      end
    end
  end
end
