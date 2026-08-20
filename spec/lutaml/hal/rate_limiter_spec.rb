# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe Lutaml::Hal::RateLimiter do
  # Fast enough that the retry examples below don't actually pause the suite.
  def fast(options = {})
    described_class.new({ base_delay: 0.001, max_delay: 0.001 }.merge(options))
  end

  def too_many_requests(retry_after = nil)
    headers = retry_after.nil? ? {} : { 'Retry-After' => retry_after }
    Lutaml::Hal::TooManyRequestsError.new('Status: 429',
                                          response: { status: 429, headers: headers })
  end

  describe '#calculate_delay' do
    context 'with a Retry-After header' do
      it 'caps the Retry-After delay at max_retry_after' do
        limiter = described_class.new(max_retry_after: 30.0)

        expect(limiter.calculate_delay(1, too_many_requests('3600'))).to eq(30.0)
      end

      it 'caps at the default max_retry_after rather than the smaller max_delay' do
        # Regression: capping server-instructed waits at max_delay (default 5s)
        # would retry far sooner than the server asked.
        limiter = described_class.new

        expect(limiter.calculate_delay(1, too_many_requests('60'))).to eq(60)
      end

      it 'honours a Retry-After delay below the cap' do
        limiter = described_class.new(max_retry_after: 30.0)

        expect(limiter.calculate_delay(1, too_many_requests('2'))).to eq(2)
      end

      it 'floors a zero Retry-After at base_delay so retries cannot busy-loop' do
        limiter = described_class.new(base_delay: 0.05)

        expect(limiter.calculate_delay(1, too_many_requests('0'))).to eq(0.05)
      end

      it 'falls back to exponential backoff when Retry-After is unparseable' do
        limiter = described_class.new(base_delay: 0.1, backoff_factor: 2.0, max_delay: 100.0)

        expect(limiter.calculate_delay(3, too_many_requests('whenever')))
          .to be_within(0.0001).of(0.4)
      end

      it 'caps a Retry-After delay carried by a ForbiddenError' do
        limiter = described_class.new(max_retry_after: 30.0, retry_on_forbidden: true)
        error = Lutaml::Hal::ForbiddenError.new('Status: 403',
                                                response: { status: 403,
                                                            headers: { 'Retry-After' => '900' } })

        expect(limiter.calculate_delay(1, error)).to eq(30.0)
      end
    end

    context 'with exponential backoff' do
      let(:limiter) { described_class.new(base_delay: 0.1, backoff_factor: 2.0, max_delay: 100.0) }

      it 'grows the delay by the backoff factor' do
        delays = (1..3).map { |attempt| limiter.calculate_delay(attempt) }

        # match, not contain_exactly: order is the whole point of backoff.
        expect(delays).to match([be_within(0.0001).of(0.1),
                                 be_within(0.0001).of(0.2),
                                 be_within(0.0001).of(0.4)])
      end

      it 'caps the backoff delay at max_delay' do
        capped = described_class.new(base_delay: 1.0, backoff_factor: 10.0, max_delay: 5.0)

        expect(capped.calculate_delay(4)).to eq(5.0)
      end
    end

    it 'falls back to backoff when a TooManyRequestsError carries no response' do
      limiter = described_class.new(base_delay: 0.1, backoff_factor: 2.0, max_delay: 100.0)

      expect(limiter.calculate_delay(1, Lutaml::Hal::TooManyRequestsError.new('boom')))
        .to be_within(0.0001).of(0.1)
    end
  end

  describe '#extract_retry_after' do
    let(:limiter) { described_class.new }

    def response_with(value)
      { status: 429, headers: { 'Retry-After' => value } }
    end

    it 'parses integer seconds' do
      expect(limiter.extract_retry_after(response_with('120'))).to eq(120)
    end

    it 'parses a lower-cased header key' do
      expect(limiter.extract_retry_after({ headers: { 'retry-after' => '30' } })).to eq(30)
    end

    it 'parses an HTTP-date into seconds from now' do
      expect(limiter.extract_retry_after(response_with((Time.now + 45).httpdate)))
        .to be_within(2).of(45)
    end

    it 'clamps a past HTTP-date to zero' do
      # calculate_delay then floors this at base_delay -- see the busy-loop example above.
      expect(limiter.extract_retry_after(response_with((Time.now - 600).httpdate))).to eq(0)
    end

    it 'returns nil for an unparseable value' do
      expect(limiter.extract_retry_after(response_with('whenever'))).to be_nil
    end

    it 'returns nil when the header is absent' do
      expect(limiter.extract_retry_after({ status: 429, headers: {} })).to be_nil
    end
  end

  describe '#should_retry?' do
    let(:limiter) { described_class.new(max_retries: 3) }

    it 'retries TooManyRequestsError within the retry budget' do
      expect(limiter.should_retry?(Lutaml::Hal::TooManyRequestsError.new, 3)).to be(true)
    end

    it 'stops once attempts exceed max_retries' do
      expect(limiter.should_retry?(Lutaml::Hal::TooManyRequestsError.new, 4)).to be(false)
    end

    it 'retries ServerError' do
      expect(limiter.should_retry?(Lutaml::Hal::ServerError.new, 1)).to be(true)
    end

    it 'does not retry unrelated errors' do
      expect(limiter.should_retry?(Lutaml::Hal::NotFoundError.new, 1)).to be(false)
    end

    it 'does not retry ForbiddenError by default' do
      expect(limiter.should_retry?(Lutaml::Hal::ForbiddenError.new, 1)).to be(false)
    end

    it 'retries ForbiddenError when retry_on_forbidden is enabled' do
      permissive = described_class.new(retry_on_forbidden: true)

      expect(permissive.should_retry?(Lutaml::Hal::ForbiddenError.new, 1)).to be(true)
    end

    it 'still honours max_retries for ForbiddenError' do
      permissive = described_class.new(max_retries: 3, retry_on_forbidden: true)

      expect(permissive.should_retry?(Lutaml::Hal::ForbiddenError.new, 4)).to be(false)
    end
  end

  describe '#retry_on_forbidden?' do
    it 'is disabled by default' do
      expect(described_class.new.retry_on_forbidden?).to be(false)
    end

    it 'is enabled when requested' do
      expect(described_class.new(retry_on_forbidden: true).retry_on_forbidden?).to be(true)
    end
  end

  describe '#with_rate_limiting' do
    it 'yields exactly once when the block succeeds' do
      calls = 0
      result = fast.with_rate_limiting do
        calls += 1
        :ok
      end

      expect([result, calls]).to eq([:ok, 1])
    end

    it 'retries up to max_retries and then re-raises' do
      limiter = fast(max_retries: 2)
      calls = 0

      expect do
        limiter.with_rate_limiting do
          calls += 1
          raise Lutaml::Hal::TooManyRequestsError, 'nope'
        end
      end.to raise_error(Lutaml::Hal::TooManyRequestsError)

      expect(calls).to eq(3)
    end

    it 'succeeds after a transient ServerError' do
      limiter = fast(max_retries: 3)
      calls = 0

      result = limiter.with_rate_limiting do
        calls += 1
        raise Lutaml::Hal::ServerError, 'boom' if calls < 2

        :recovered
      end

      expect([result, calls]).to eq([:recovered, 2])
    end

    it 'does not retry ForbiddenError by default' do
      limiter = fast
      calls = 0

      expect do
        limiter.with_rate_limiting do
          calls += 1
          raise Lutaml::Hal::ForbiddenError, 'denied'
        end
      end.to raise_error(Lutaml::Hal::ForbiddenError)

      expect(calls).to eq(1)
    end

    it 'retries ForbiddenError when retry_on_forbidden is enabled' do
      limiter = fast(max_retries: 1, retry_on_forbidden: true)
      calls = 0

      expect do
        limiter.with_rate_limiting do
          calls += 1
          raise Lutaml::Hal::ForbiddenError, 'denied'
        end
      end.to raise_error(Lutaml::Hal::ForbiddenError)

      expect(calls).to eq(2)
    end

    it 'does not retry while disabled' do
      limiter = described_class.new(enabled: false)
      calls = 0

      expect do
        limiter.with_rate_limiting do
          calls += 1
          raise Lutaml::Hal::TooManyRequestsError, 'nope'
        end
      end.to raise_error(Lutaml::Hal::TooManyRequestsError)

      expect(calls).to eq(1)
    end
  end
end
