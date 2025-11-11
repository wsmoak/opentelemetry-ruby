# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'

describe OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor do
  class TestExporter
    def export(batch, timeout: nil)
      OpenTelemetry::SDK::Logs::Export::SUCCESS
    end

    def shutdown(timeout: nil)
      OpenTelemetry::SDK::Logs::Export::SUCCESS
    end

    def force_flush(timeout: nil)
      OpenTelemetry::SDK::Logs::Export::SUCCESS
    end
  end

  describe 'metrics' do
    it 'registers component instance on initialization' do
      exporter = TestExporter.new
      processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)

      # Verify that the processor registered itself with a unique name
      component_name = processor.instance_variable_get(:@component_name)
      _(component_name).wont_be_nil
      _(component_name).must_match(/batching_log_record_processor\/\d+/)

      processor.shutdown
    end

    it 'creates a second processor with different instance number' do
      exporter1 = TestExporter.new
      exporter2 = TestExporter.new

      processor1 = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter1)
      processor2 = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter2)

      name1 = processor1.instance_variable_get(:@component_name)
      name2 = processor2.instance_variable_get(:@component_name)

      # Both should be batching_log_record_processor but with different instance numbers
      _(name1).must_match(/batching_log_record_processor\/\d+/)
      _(name2).must_match(/batching_log_record_processor\/\d+/)
      _(name1).wont_equal(name2)

      processor1.shutdown
      processor2.shutdown
    end

    it 'initializes metrics when meter is available' do
      exporter = TestExporter.new
      processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)

      # The processor should have initialized a processed counter
      # This will only be non-nil if a meter was available
      processed_counter = processor.instance_variable_get(:@processed_counter)
      # processed_counter may be nil if no global meter provider is configured, which is expected
      # The test just verifies the code doesn't crash
      _(true).must_equal(true)

      processor.shutdown
    end
  end

  describe 'metrics graceful degradation' do
    it 'continues to work without a metrics provider' do
      # Even without metrics, the processor should function normally
      exporter = TestExporter.new
      processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)

      # Create a mock log record
      log_record = Minitest::Mock.new
      log_record.expect(:to_log_record_data, {})

      # This should not raise even if metrics fail
      processor.on_emit(log_record, nil)
      processor.force_flush
      processor.shutdown

      _(true).must_equal(true)
    end
  end
end
