# frozen_string_literal: true

# Memory leak smoke tests for FFI resource deallocation.
#
# Usage:
#   MEM_TEST=1 bundle exec rake test
#
# Methodology:
#   We repeatedly execute a set of commands and measure RSS growth.
#   Fail if RSS grew > 10%. This catches obvious leaks, like
#   forgetting to free a C struct or buffer.
#
# Blind spots:
#   - Slow leaks that don't reach 10% within the iteration count
#   - Leaks in error/edge-case paths not exercised here

module ValkeyTests
  module MemoryLeak
    ITERATIONS = 1000
    MAX_RSS_GROWTH_PERCENT = 10.0

    private

    def process_rss_kb
      # Force GC before measurement for consistency
      GC.start
      GC.compact if GC.respond_to?(:compact)

      case RUBY_PLATFORM
      when /linux/
        File.read("/proc/#{Process.pid}/statm").split[1].to_i * (page_size / 1024)
      when /darwin/
        `ps -o rss= -p #{Process.pid}`.strip.to_i
      else
        # Fallback: use ps (works on most Unix)
        `ps -o rss= -p #{Process.pid}`.strip.to_i
      end
    end

    def page_size
      @page_size ||= `getconf PAGE_SIZE`.strip.to_i
    end

    def skip_unless_mem_test
      skip "Set MEM_TEST=1 to run memory leak tests" unless ENV["MEM_TEST"]
    end

    def assert_no_leak(initial_rss, label)
      final_rss = process_rss_kb
      growth_percent = ((final_rss - initial_rss).to_f / initial_rss) * 100

      assert growth_percent < MAX_RSS_GROWTH_PERCENT,
             "RSS grew by #{growth_percent.round(2)}% after #{ITERATIONS} #{label} — " \
             "possible memory leak (threshold: #{MAX_RSS_GROWTH_PERCENT}%)"
    end

    public

    def test_command_no_memory_leak
      skip_unless_mem_test

      # Warmup — let allocators stabilize
      100.times { r.set("warmup", "x") }
      100.times { r.get("warmup") }

      initial_rss = process_rss_kb

      ITERATIONS.times do |i|
        r.set("leak_test_#{i % 100}", "value_#{i}")
        r.get("leak_test_#{i % 100}")
      end

      assert_no_leak(initial_rss, "command cycles")
    end

    def test_script_load_no_memory_leak
      skip_unless_mem_test

      # Warmup
      10.times { r.script_load("return 1") }

      initial_rss = process_rss_kb

      ITERATIONS.times do |i|
        r.script_load("return #{i}")
      end

      assert_no_leak(initial_rss, "script_load calls")
    end

    def test_eval_no_memory_leak
      skip_unless_mem_test

      # Warmup
      10.times { r.eval("return 1") }

      initial_rss = process_rss_kb

      ITERATIONS.times do |i|
        script = "return #{i % 100}"
        r.eval(script, keys: ["k#{i % 10}"], args: ["a#{i % 10}"])
      end

      assert_no_leak(initial_rss, "eval calls")
    end

    def test_pipeline_no_memory_leak
      skip_unless_mem_test

      # Warmup
      5.times do
        r.pipelined do |pipe|
          10.times { |i| pipe.set("warmup_#{i}", "v") }
        end
      end

      initial_rss = process_rss_kb

      ITERATIONS.times do |i|
        r.pipelined do |pipe|
          pipe.set("pipe_#{i % 100}", "value_#{i}")
          pipe.get("pipe_#{i % 100}")
          pipe.incr("pipe_counter")
        end
      end

      assert_no_leak(initial_rss, "pipeline batches")
    end
  end
end
