# frozen_string_literal: true

require 'rspec'
require 'faraday'
require 'lutaml-hal'

# End-to-end proof that the register coalesces concurrent fetches of the same
# URL into a single HTTP request (single-flight), using a real stubbed client.
RSpec.describe 'ModelRegister single-flight coalescing' do
  let(:calls) { { n: 0 } }
  let(:calls_mutex) { Mutex.new }
  let(:gate) { Queue.new }

  let(:model_class) { Class.new(Lutaml::Hal::Resource) { attribute :id, :string } }

  let(:stubs) do
    counter = calls
    mutex = calls_mutex
    release = gate
    Faraday::Adapter::Test::Stubs.new(strict_mode: false) do |stub|
      stub.get('/things/1') do |_env|
        mutex.synchronize { counter[:n] += 1 }
        release.pop # hold the in-flight request so concurrent callers coalesce
        [200, { 'Content-Type' => 'application/json' },
         { 'id' => '1', '_links' => { 'self' => { 'href' => '/things/1' } } }.to_json]
      end
    end
  end

  let(:register) do
    conn = Faraday.new do |f|
      f.response :json, content_type: /json/
      f.adapter :test, stubs
    end
    client = Lutaml::Hal::Client.new(api_url: 'https://api.example.com', connection: conn)
    reg = Lutaml::Hal::ModelRegister.new(name: :sf_test, client: client, cache: { adapter: :memory })
    Lutaml::Hal::GlobalRegister.instance.unregister(:sf_test)
    Lutaml::Hal::GlobalRegister.instance.register(:sf_test, reg)
    reg.add_endpoint(
      id: :thing, type: :resource, url: '/things/{id}', model: model_class,
      parameters: [Lutaml::Hal::EndpointParameter.new(name: 'id', in: :path, required: true)]
    )
    reg
  end

  it 'makes a single HTTP request for concurrent fetches of the same URL' do
    threads = Array.new(6) { Thread.new { register.fetch(:thing, id: '1') } }

    sleep 0.15 # let all six reach the coalesce point
    # release; with coalescing only the leader pops, the extras are harmless
    6.times { gate << :go }

    results = threads.map(&:value)

    expect(calls[:n]).to eq(1)
    expect(results).to all(be_a(model_class))
  end
end
