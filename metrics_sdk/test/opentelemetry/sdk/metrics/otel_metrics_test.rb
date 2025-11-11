# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

require 'test_helper'
require 'opentelemetry/sdk/metrics/otel_metrics'

describe OpenTelemetry::SDK::Metrics::OTelMetrics do
  describe 'constants' do
    it 'defines OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE).must_equal('otel.sdk.processor.log.queue.size')
    end

    it 'defines OTEL_SDK_PROCESSOR_LOG_QUEUE_CAPACITY' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_LOG_QUEUE_CAPACITY).must_equal('otel.sdk.processor.log.queue.capacity')
    end

    it 'defines OTEL_SDK_PROCESSOR_LOG_PROCESSED' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_LOG_PROCESSED).must_equal('otel.sdk.processor.log.processed')
    end

    it 'defines OTEL_SDK_PROCESSOR_SPAN_QUEUE_SIZE' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_SPAN_QUEUE_SIZE).must_equal('otel.sdk.processor.span.queue.size')
    end

    it 'defines OTEL_SDK_PROCESSOR_SPAN_QUEUE_CAPACITY' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_SPAN_QUEUE_CAPACITY).must_equal('otel.sdk.processor.span.queue.capacity')
    end

    it 'defines OTEL_SDK_PROCESSOR_SPAN_PROCESSED' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_PROCESSOR_SPAN_PROCESSED).must_equal('otel.sdk.processor.span.processed')
    end

    it 'defines exporter metrics' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_EXPORTER_SPAN_EXPORTED).must_equal('otel.sdk.exporter.span.exported')
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_EXPORTER_LOG_EXPORTED).must_equal('otel.sdk.exporter.log.exported')
    end

    it 'defines span lifecycle metrics' do
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_SPAN_STARTED).must_equal('otel.sdk.span.started')
      _(OpenTelemetry::SDK::Metrics::OTelMetrics::OTEL_SDK_SPAN_LIVE).must_equal('otel.sdk.span.live')
    end
  end

  describe 'factory methods' do
    it 'creates counter for log queue size' do
      meter = Minitest::Mock.new
      meter.expect(:create_up_down_counter, nil) { |**kwargs| true }
      OpenTelemetry::SDK::Metrics::OTelMetrics.create_otel_sdk_processor_log_queue_size(meter)
      meter.verify
    end

    it 'creates counter for span queue size' do
      meter = Minitest::Mock.new
      meter.expect(:create_up_down_counter, nil) { |**kwargs| true }
      OpenTelemetry::SDK::Metrics::OTelMetrics.create_otel_sdk_processor_span_queue_size(meter)
      meter.verify
    end

    it 'creates counter for processed spans' do
      meter = Minitest::Mock.new
      meter.expect(:create_counter, nil) { |**kwargs| true }
      OpenTelemetry::SDK::Metrics::OTelMetrics.create_otel_sdk_processor_span_processed(meter)
      meter.verify
    end
  end
end
