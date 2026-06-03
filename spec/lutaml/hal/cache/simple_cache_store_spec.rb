# frozen_string_literal: true

require 'rspec'
require_relative '../../../../lib/lutaml/hal/cache/simple_cache_store'

RSpec.describe Lutaml::Hal::Cache::SimpleCacheStore do
  subject(:store) { described_class.new(3) }

  it 'stores and retrieves values' do
    store.set('a', 1)
    expect(store.get('a')).to eq(1)
    expect(store.get('missing')).to be_nil
  end

  it 'reports size and deletes/clears' do
    store.set('a', 1)
    store.set('b', 2)
    expect(store.size).to eq(2)
    store.delete('a')
    expect(store.get('a')).to be_nil
    expect(store.size).to eq(1)
    store.clear
    expect(store.size).to eq(0)
  end

  it 'evicts the least-recently-used entry past max_size' do
    store.set('a', 1)
    store.set('b', 2)
    store.set('c', 3)
    store.get('a')        # 'a' is now most-recently used, 'b' is LRU
    store.set('d', 4)     # evicts 'b'
    expect(store.get('b')).to be_nil
    expect(store.get('a')).to eq(1)
    expect(store.get('d')).to eq(4)
    expect(store.size).to eq(3)
  end

  it 'is safe under concurrent access' do
    store = described_class.new(50)
    threads = Array.new(8) do |t|
      Thread.new do
        300.times do |i|
          key = "key#{(i * 7 + t) % 120}"
          store.set(key, "#{t}-#{i}")
          store.get(key)
          store.delete("key#{i % 120}") if i.even?
        end
      end
    end

    expect { threads.each(&:join) }.not_to raise_error
    # LRU bookkeeping stayed consistent: size never runs away past the cap.
    expect(store.size).to be <= 50
    expect(store.stats[:keys].size).to eq(store.size)
  end
end
