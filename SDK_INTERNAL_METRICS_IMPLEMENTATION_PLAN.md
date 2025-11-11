# Implementation Plan: SDK Internal Metrics for OpenTelemetry Ruby

## Overview

The Python project has already implemented the semantic conventions template for SDK metrics (using Weaver code generation). Ruby needs to create a similar code generation approach and then integrate actual metric emission into the `BatchLogRecordProcessor` and other SDK components.

This plan describes how to implement the semantic conventions for OpenTelemetry SDK metrics in the opentelemetry-ruby project, starting with `otel.sdk.processor.log.queue.size` and extending to all SDK internal metrics.

## Reference Specifications

- **Semantic Conventions Spec**: [Semantic conventions for OpenTelemetry SDK metrics](https://opentelemetry.io/docs/specs/semconv/system_metrics/)
- **Generated Constants**: `lib/opentelemetry/semconv/incubating/otel/metrics.rb` (auto-generated from upstream)
- **Generated Attributes**: `lib/opentelemetry/semconv/incubating/otel/attributes.rb` (includes `error.type`, `otel.component.name`, `otel.component.type`)

## SDK Metrics Overview

### Metric Categories

#### Exporter Metrics (6 metrics)
- `otel.sdk.exporter.span.exported` - Number of spans successfully or failed to export
- `otel.sdk.exporter.span.inflight` - Spans waiting to be exported
- `otel.sdk.exporter.log.exported` - Number of log records exported
- `otel.sdk.exporter.log.inflight` - Log records awaiting export
- `otel.sdk.exporter.metric_data_point.exported` - Metric data points exported
- `otel.sdk.exporter.metric_data_point.inflight` - Metric data points in flight
- `otel.sdk.exporter.operation.duration` - Duration of batch export operations (histogram)

#### Processor Metrics (6 metrics)
- `otel.sdk.processor.span.processed` - Spans processed (successful/failed)
- `otel.sdk.processor.span.queue.size` - Current spans in processor queue
- `otel.sdk.processor.span.queue.capacity` - Maximum queue capacity for spans
- `otel.sdk.processor.log.processed` - Log records processed
- `otel.sdk.processor.log.queue.size` - Current log records in queue
- `otel.sdk.processor.log.queue.capacity` - Maximum log record queue capacity

#### SDK Span Metrics (4 metrics)
- `otel.sdk.span.started` - Total spans created (counter)
- `otel.sdk.span.live` - Active spans with recording=true
- (2 deprecated metrics for backward compatibility)

#### Other SDK Metrics (2 metrics)
- `otel.sdk.log.created` - Log records submitted to enabled SDK Loggers
- `otel.sdk.metric_reader.collection.duration` - Metric reader collection operation duration

### Instrument Types

- **Counter**: Monotonically increasing values (spans/logs processed)
- **UpDownCounter**: Values that can increase or decrease (queue sizes, inflight counts)
- **Histogram**: Distribution of values (operation durations)

### Units

- Queue sizes: `{log_record}` or `{span}`
- Durations: `s` (seconds)
- Other counts: `{log_record}`, `{span}`, `{data_point}`

### Required Attributes

- **error.type**: For failed operations, contains the failure cause (e.g., "timeout", "rejected")
- **otel.component.name**: Unique instance identifier (e.g., `batching_log_record_processor/0`)
- **otel.component.type**: Component type identifier (e.g., `batching_log_record_processor`)

---

## Phase 1: Code Generation Setup

### 1.1 Create a new Ruby metrics template

**File**: `semantic_conventions/templates/registry/ruby/sdk_metrics.j2`

**Purpose**: Generate metric constants and factory functions for SDK metrics

**Pattern**: Should generate both:
- Constants like `OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE = "otel.sdk.processor.log.queue.size"`
- Factory functions like:
  ```ruby
  def self.create_otel_sdk_processor_log_queue_size(meter)
    meter.create_up_down_counter(
      name: OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE,
      description: "The number of log records in the queue of a given instance of an SDK log processor.",
      unit: "{log_record}"
    )
  end
  ```

**Output location**: `lib/opentelemetry/sdk/metrics/otel_metrics.rb` (in `metrics_sdk` gem)

**Key implementation details**:
- Import the generated metric constants from `OpenTelemetry::SemConv::Incubating::Otel::Metrics`
- Use text_maps in weaver.yaml to convert instrument types:
  - `updowncounter` → `up_down_counter` (factory method)
  - `counter` → `counter`
  - `histogram` → `histogram`
  - `gauge` → `observable_gauge`
- Support optional description, unit, and other metadata
- Handle deprecated metrics gracefully
- Follow Ruby conventions (snake_case for method names)

### 1.2 Update weaver.yaml configuration

**File**: `semantic_conventions/templates/registry/ruby/weaver.yaml`

**Changes**:
- Add configuration for the new `sdk_metrics.j2` template
- Specify output path for SDK metrics
- Set up text_maps for Ruby instrument type mapping
- Include the SDK metrics namespace (otel.sdk.*)

**Example configuration**:
```yaml
templates:
  - template: sdk_metrics.j2
    output: '{{root_namespace}}/otel_metrics.rb'
    filter: all
```

### 1.3 Update Rakefile

**File**: `semantic_conventions/Rakefile`

**Changes**:
- Ensure `rake generate` task processes the new `sdk_metrics.j2` template
- Add any necessary weaver.toml configuration for SDK metrics if needed
- Verify the generated file is committed to git or included in the gem

---

## Phase 2: Implement Metric Emission in Processors

### 2.1 Update BatchLogRecordProcessor

**File**: `logs_sdk/lib/opentelemetry/sdk/logs/export/batch_log_record_processor.rb`

**Metrics to add**:
- `otel.sdk.processor.log.queue.size` (UpDownCounter)
  - Observable callback that returns current `@log_records.size`
  - Attributes: `otel.component.name`
- `otel.sdk.processor.log.queue.capacity` (UpDownCounter)
  - Observable callback that returns `@max_queue_size`
  - Attributes: `otel.component.name`
- `otel.sdk.processor.log.processed` (Counter)
  - Incremented on successful batch export
  - Attributes: `otel.component.name`, `error.type` (only if failed)

**Implementation pattern**:
1. During initialization:
   - Get instance counter from InternalMetrics registry
   - Create `otel.component.name` attribute (e.g., "batching_log_record_processor/0")
   - Register observable callbacks for queue size/capacity
   - Create the counter instrument

2. During `on_emit`:
   - No direct metric updates needed for queue size (observable callback handles it)

3. During batch export:
   - Increment counter on successful export
   - If export fails, increment with `error.type` attribute

4. During shutdown:
   - Unregister callbacks and clean up
   - Remove instance from registry

**Example code structure**:
```ruby
def initialize(exporter, ...)
  # ... existing code ...

  @component_name = InternalMetrics.register_processor_instance('batching_log_record_processor')

  # Only attempt to create metrics if a metrics provider is available
  if metrics_provider = InternalMetrics.metrics_provider
    meter = metrics_provider.meter(name: 'opentelemetry-sdk', version: VERSION)

    # Register observable callbacks for queue sizes
    meter.create_up_down_counter(
      name: OpenTelemetry::SDK::Metrics::OtelMetrics::OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE,
      description: "The number of log records in the queue of a given instance of an SDK log processor.",
      unit: "{log_record}",
      callbacks: [
        ->(options) {
          [OpenTelemetry::SDK::Metrics::Observation.new(
            @log_records.size,
            {'otel.component.name' => @component_name}
          )]
        }
      ]
    )

    @processed_counter = meter.create_counter(
      name: OpenTelemetry::SDK::Metrics::OtelMetrics::OTEL_SDK_PROCESSOR_LOG_PROCESSED,
      description: "The number of log records for which the processing has finished, either successful or failed.",
      unit: "{log_record}"
    )
  end
end

def export_batch(batch, timeout: @exporter_timeout_seconds)
  result_code = @export_mutex.synchronize { @exporter.export(batch, timeout: timeout) }
  report_result(result_code, batch)

  # Emit metric
  if @processed_counter
    attributes = {'otel.component.name' => @component_name}
    attributes['error.type'] = 'export_error' if result_code != SUCCESS
    @processed_counter.add(batch.size, attributes: attributes)
  end

  result_code
end
```

### 2.2 Update BatchSpanProcessor

**File**: `sdk/lib/opentelemetry/sdk/trace/export/batch_span_processor.rb`

**Similar changes** to BatchLogRecordProcessor:
- `otel.sdk.processor.span.queue.size` (UpDownCounter)
- `otel.sdk.processor.span.queue.capacity` (UpDownCounter)
- `otel.sdk.processor.span.processed` (Counter)

**Note**: Span processor is in the main `sdk` gem, not `logs_sdk`

### 2.3 Add metrics to MeterProvider

**File**: `metrics_sdk/lib/opentelemetry/sdk/metrics/meter_provider.rb`

**Purpose**: Initialize metrics that need a reference to the global meter provider

**Metrics to add**:
- `otel.sdk.span.started` (Counter)
  - Increment when a new span is created in LoggerProvider
  - Attributes: optional error attributes if creation fails

- `otel.sdk.span.live` (UpDownCounter)
  - Observable callback tracking active spans
  - May require integration with SpanProcessor

- `otel.sdk.log.created` (Counter)
  - Increment when a new log record is emitted
  - Attributes: optional error attributes if creation fails

**Implementation considerations**:
- These metrics require access to the MeterProvider itself, so they should be initialized early
- May need to hook into LoggerProvider creation as well
- Observable callbacks for `live` spans need to query the current span context

---

## Phase 3: Helper Infrastructure

### 3.1 Create an InternalMetrics module

**File**: `sdk/lib/opentelemetry/sdk/internal_metrics.rb`

**Purpose**: Centralize metric creation and instance tracking

**Features**:
- Registry to track all processor instances with unique names
- Counter to auto-increment instance IDs (e.g., processor/0, processor/1, processor/2)
- Safe access to the global meter
- Observable callback registration helpers
- Thread-safe operations

**Example interface**:
```ruby
module OpenTelemetry
  module SDK
    module InternalMetrics
      # Register a processor instance and return its unique name
      def self.register_processor_instance(type)
        # Returns "batching_log_record_processor/0", "batching_log_record_processor/1", etc.
      end

      # Get the global metrics provider (if available)
      def self.metrics_provider
        # Return the global MeterProvider or nil if not configured
      end

      # Clean up on processor shutdown
      def self.unregister_processor_instance(name)
        # Remove from registry
      end
    end
  end
end
```

**Implementation details**:
- Use a class variable with Mutex for thread safety
- Handle race conditions when multiple processors start simultaneously
- Consider how this interacts with forking (should reset on fork)
- Should not raise exceptions if metrics provider is unavailable

### 3.2 Update MeterProvider to expose metrics meter

**File**: `metrics_sdk/lib/opentelemetry/sdk/metrics/meter_provider.rb`

**Changes**:
- Ensure a special internal meter is available for SDK component metrics
- This meter should be accessible to processors without circular dependencies
- Consider creating a separate MeterProvider for internal metrics to avoid conflicts
- The internal meter should NOT be exported; it's purely for internal SDK observability

**Pattern**:
```ruby
class MeterProvider
  def self.internal_meter
    # Return a meter specifically for SDK internal metrics
    # This could be the same provider or a separate one
  end
end
```

---

## Phase 4: Testing & Documentation

### 4.1 Add tests

**Test files to create**:
- `metrics_sdk/test/opentelemetry/sdk/metrics/otel_metrics_test.rb`
  - Test that constants are properly defined
  - Test factory functions return correct instrument types

- `logs_sdk/test/opentelemetry/sdk/logs/export/batch_log_record_processor_metrics_test.rb`
  - Test observable callbacks return correct queue sizes
  - Test counter increments on batch export
  - Test attribute labels (component.name, error.type)
  - Test that metrics are skipped if metrics provider unavailable

- `sdk/test/opentelemetry/sdk/trace/export/batch_span_processor_metrics_test.rb`
  - Similar tests for span processor

- `sdk/test/opentelemetry/sdk/internal_metrics_test.rb`
  - Test instance registry
  - Test unique naming
  - Test thread safety

**Test coverage**:
- ✅ Metric constants are generated and accessible
- ✅ Factory functions create correct instrument types with correct names/descriptions/units
- ✅ Observable callbacks are called and return correct values
- ✅ Counters increment with correct attributes
- ✅ Metrics work with multiple processor instances
- ✅ Metrics degrade gracefully when metrics provider unavailable
- ✅ No circular dependencies between SDK components

### 4.2 Documentation

**Files to update/create**:
- `README.md` - Add section on SDK internal metrics
- `docs/sdk_metrics.md` - Comprehensive guide to SDK metrics
- Inline YARD documentation in the code

**Documentation content**:
- Overview of what SDK metrics are available
- Why these metrics matter (debugging, monitoring SDK health)
- How to configure the metrics provider
- Example metrics output
- The `otel.component.name` naming convention
- Stability level of metrics (currently "development")
- Known limitations (e.g., metrics only available with metrics SDK configured)

---

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **UpDownCounter for queue sizes** | Matches spec; allows both increment/decrement operations; additive across instances |
| **Observable callbacks** | Queue size shouldn't require manual increment/decrement; just observe current state |
| **Separate template (sdk_metrics.j2)** | Keeps SDK metrics separate from semantic conventions, allowing independent updates |
| **Module in `sdk` gem** | InternalMetrics module in base SDK gem for span/log processors to access without circular deps |
| **Auto-generate from spec** | Uses Weaver so metrics stay in sync with upstream semantic conventions |
| **Graceful degradation** | Processors should work even if metrics provider unavailable (no exceptions, just skip metrics) |
| **Optional component.name** | Allow metrics to work even if instance registry unavailable |
| **Separate internal meter** | Avoid conflicts with user-configured meters and metrics |

---

## Implementation Timeline

### Week 1: Code Generation
- [ ] Create `sdk_metrics.j2` template
- [ ] Update `weaver.yaml` configuration
- [ ] Update `Rakefile` to generate SDK metrics
- [ ] Test code generation produces correct output

### Week 2: Infrastructure & Foundation
- [ ] Create `InternalMetrics` module with instance registry
- [ ] Update `MeterProvider` to provide internal meter access
- [ ] Add basic tests for infrastructure

### Week 3: BatchLogRecordProcessor Metrics
- [ ] Implement queue size/capacity observable callbacks
- [ ] Implement processed counter with error handling
- [ ] Add comprehensive tests
- [ ] Update documentation

### Week 4: BatchSpanProcessor Metrics & Polish
- [ ] Implement span processor metrics
- [ ] Add integration tests
- [ ] Update README and documentation
- [ ] Code review and final adjustments

---

## Expected Output Example

After implementation, the generated `lib/opentelemetry/sdk/metrics/otel_metrics.rb` will contain:

```ruby
# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module SDK
    module Metrics
      module OtelMetrics
        OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE = "otel.sdk.processor.log.queue.size"
        # The number of log records in the queue of a given instance of an SDK log processor
        # Instrument: updowncounter
        # Unit: {log_record}
        # Note: Only applies to log record processors which use a queue, e.g. the SDK Batching Log Record Processor.

        def self.create_otel_sdk_processor_log_queue_size(meter)
          meter.create_up_down_counter(
            name: OTEL_SDK_PROCESSOR_LOG_QUEUE_SIZE,
            description: "The number of log records in the queue of a given instance of an SDK log processor.",
            unit: "{log_record}"
          )
        end

        OTEL_SDK_PROCESSOR_LOG_QUEUE_CAPACITY = "otel.sdk.processor.log.queue.capacity"
        # The maximum number of log records the queue of a given instance of an SDK Log Record processor can hold
        # Instrument: updowncounter
        # Unit: {log_record}

        def self.create_otel_sdk_processor_log_queue_capacity(meter)
          meter.create_up_down_counter(
            name: OTEL_SDK_PROCESSOR_LOG_QUEUE_CAPACITY,
            description: "The maximum number of log records the queue of a given instance of an SDK Log Record processor can hold.",
            unit: "{log_record}"
          )
        end

        OTEL_SDK_PROCESSOR_LOG_PROCESSED = "otel.sdk.processor.log.processed"
        # The number of log records for which the processing has finished, either successful or failed
        # Instrument: counter
        # Unit: {log_record}

        def self.create_otel_sdk_processor_log_processed(meter)
          meter.create_counter(
            name: OTEL_SDK_PROCESSOR_LOG_PROCESSED,
            description: "The number of log records for which the processing has finished, either successful or failed.",
            unit: "{log_record}"
          )
        end

        # ... more metrics ...
      end
    end
  end
end
```

And the `BatchLogRecordProcessor` will have observable callbacks and counter updates with appropriate attributes.

---

## Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| **Circular dependencies** | Keep InternalMetrics in base SDK gem; use lazy loading for MeterProvider access |
| **Missing metrics provider** | Gracefully degrade; don't throw exceptions if metrics unavailable |
| **Performance overhead** | Observable callbacks are lightweight; metric updates are non-blocking |
| **Thread safety** | Use Mutex for instance registry; ensure all metric operations are thread-safe |
| **Forking issues** | Reset instance counters on fork; use OpenTelemetry's fork_hooks mechanism |
| **Breaking changes** | This is additive; existing code continues to work unchanged |

---

## Future Enhancements

- [ ] Add exporter metrics (inflight counts, operation durations)
- [ ] Add metric reader collection duration tracking
- [ ] Add span lifecycle metrics (started, live)
- [ ] Add log lifecycle metrics (created)
- [ ] Support for custom error types beyond basic "error"
- [ ] Metrics aggregation/summarization helpers
- [ ] Built-in dashboards/visualizations for SDK metrics

---

## References

- OpenTelemetry Python Implementation: `/Users/wsmoak/Projects/opentelemetry-python/opentelemetry-semantic-conventions/src/opentelemetry/semconv/_incubating/metrics/otel_metrics.py`
- Ruby Batch Processor: `/Users/wsmoak/Projects/opentelemetry-ruby/logs_sdk/lib/opentelemetry/sdk/logs/export/batch_log_record_processor.rb`
- Python Template: `/Users/wsmoak/Projects/opentelemetry-python/scripts/semconv/templates/registry/semantic_metrics.j2`
- Ruby Metrics Template: `/Users/wsmoak/Projects/opentelemetry-ruby/semantic_conventions/templates/registry/ruby/metrics.j2`
- Semantic Conventions (Generated): `/Users/wsmoak/Projects/opentelemetry-ruby/semantic_conventions/lib/opentelemetry/semconv/incubating/otel/metrics.rb`
