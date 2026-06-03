# frozen_string_literal: true

require 'rspec'
require 'timeout'
require_relative '../../../lib/lutaml/hal/single_flight'

RSpec.describe Lutaml::Hal::SingleFlight do
  subject(:single_flight) { described_class.new }

  it 'returns the block result' do
    expect(single_flight.run('k') { 42 }).to eq(42)
  end

  it 'runs the block once for concurrent same-key calls and shares the result' do
    count = 0
    count_mutex = Mutex.new
    gate = Queue.new # the leader blocks here until released

    threads = Array.new(8) do
      Thread.new do
        single_flight.run('same') do
          count_mutex.synchronize { count += 1 }
          gate.pop
          'result'
        end
      end
    end

    sleep 0.1     # let all 8 threads reach run() and coalesce onto the leader
    gate << :go   # release the single leader
    results = threads.map(&:value)

    expect(count).to eq(1)
    expect(results).to all(eq('result'))
  end

  it 'runs different keys in parallel (no cross-key blocking)' do
    a_started = Queue.new
    b_started = Queue.new

    # Each key's block waits for the other to start. If different keys were
    # serialized this would deadlock; the timeout turns that into a failure.
    run_key = lambda do |key, mine, other|
      single_flight.run(key) do
        mine << 1
        other.pop
        key
      end
    end

    result = Timeout.timeout(5) do
      ta = Thread.new { run_key.call('a', a_started, b_started) }
      tb = Thread.new { run_key.call('b', b_started, a_started) }
      [ta.value, tb.value]
    end

    expect(result).to eq(%w[a b])
  end

  it 'propagates the leader error to every waiter' do
    gate = Queue.new

    threads = Array.new(4) do
      Thread.new do
        single_flight.run('err') do
          gate.pop
          raise 'boom'
        end
      rescue StandardError => e
        e.message
      end
    end

    sleep 0.1
    gate << :go
    expect(threads.map(&:value)).to all(eq('boom'))
  end

  it 'allows the key to be fetched again after a call completes' do
    single_flight.run('k') { 1 }
    expect(single_flight.run('k') { 2 }).to eq(2)
  end
end
