require "spec_helper"
require "active_support/core_ext/hash/keys"
require "support/json_api_lint"

DummyEvent = Class.new(::RailsEventStore::Event)

module RailsEventStore
  RSpec.describe Browser, type: :request do
    include SchemaHelper

    before { load_database_schema }

    specify do
      event_store.publish_event(dummy_event, stream_name: "dummy")
      get "/res/streams"

      expect(response).to have_http_status(200)
      expect(parsed_body["data"]).to match_array([all_stream_resource, dummy_stream_resource])
      expect(parsed_body["links"]).to eq({})
    end

    specify "first page, newest streams descending" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      get "/res/streams"

      expect(parsed_body["links"]).to eq({
        "last" => "http://www.example.com/res/streams/head/forward/20",
        "next" => "http://www.example.com/res/streams/#{first_page.last}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "first page, newest streams descending" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      get "/res/streams/head/backward/20"

      expect(parsed_body["links"]).to eq({
        "last" => "http://www.example.com/res/streams/head/forward/20",
        "next" => "http://www.example.com/res/streams/#{first_page.last}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "first page, newest streams descending" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      last_page  = streams.reverse.drop(20)
      get "/res/streams/#{last_page.first}/forward/20"

      expect(parsed_body["links"]).to eq({
        "last" => "http://www.example.com/res/streams/head/forward/20",
        "next" => "http://www.example.com/res/streams/#{first_page.last}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "last page, oldest events descending" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      last_page  = streams.reverse.drop(20)
      get "/res/streams/#{first_page.last}/backward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/head/backward/20",
        "prev"  => "http://www.example.com/res/streams/#{last_page.first}/forward/20" ,
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "last page, oldest events descending" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      last_page  = streams.reverse.drop(20)
      get "/res/streams/head/forward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/head/backward/20",
        "prev"  => "http://www.example.com/res/streams/#{last_page.first}/forward/20" ,
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "non-edge page" do
      streams = 40.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      next_page  = streams.reverse.drop(20)
      get "/res/streams/#{first_page.last}/backward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/head/backward/20",
        "last"  => "http://www.example.com/res/streams/head/forward/20",
        "next"  => "http://www.example.com/res/streams/#{next_page.last}/backward/20",
        "prev"  => "http://www.example.com/res/streams/#{next_page.first}/forward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end
    
    specify do
      streams = 20.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      current_page = streams.reverse.drop(1) + ["all"]
      get "/res/streams/head/forward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/head/backward/20",
        "prev"  => "http://www.example.com/res/streams/#{current_page.first}/forward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "custom page size" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(5)
      next_page  = streams.reverse.drop(5).take(5)
      get "/res/streams/#{first_page.last}/backward/5"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/head/backward/5",
        "last"  => "http://www.example.com/res/streams/head/forward/5",
        "next"  => "http://www.example.com/res/streams/#{next_page.last}/backward/5",
        "prev"  => "http://www.example.com/res/streams/#{next_page.first}/forward/5"
      })
      expect(parsed_body["data"].size).to eq(5)
    end

    specify "out of bounds beyond oldest" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      last_page = streams.reverse.drop(20) + ["all"]
      get "/res/streams/#{last_page.last}/backward/20"

      expect(parsed_body["links"]).to eq({})
      expect(parsed_body["data"].size).to eq(0)
    end

    specify "out of bounds beyond newest" do
      streams = 39.times.map { |i| "stream_#{i}" }
      streams.each { |stream_name| event_store.publish_event(DummyEvent.new, stream_name: stream_name) }
      first_page = streams.reverse.take(20)
      get "/res/streams/#{first_page.first}/forward/20"

      expect(parsed_body["links"]).to eq({})
      expect(parsed_body["data"].size).to eq(0)
    end

    specify do
      event_store.publish_event(dummy_event, stream_name: "dummy")
      get "/res/streams/all"

      expect(response).to have_http_status(200)
      expect(parsed_body["data"]).to match_array([event_resource])

      get "/res/streams/dummy"

      expect(response).to have_http_status(200)
      expect(parsed_body["data"]).to match_array([event_resource])
    end

    specify do
      event_store.publish_event(dummy_event, stream_name: "dummy")
      get "/res/events/#{dummy_event.event_id}"

      expect(response).to have_http_status(200)
      expect(parsed_body["data"]).to match(event_resource)
    end

    specify "first page, newest events descending" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy"

      expect(parsed_body["links"]).to eq({
        "last"  => "http://www.example.com/res/streams/dummy/head/forward/20",
        "next"  => "http://www.example.com/res/streams/dummy/#{first_page.last.event_id}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "first page, newest events descending" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/head/backward/20"

      expect(parsed_body["links"]).to eq({
        "last"  => "http://www.example.com/res/streams/dummy/head/forward/20",
        "next"  => "http://www.example.com/res/streams/dummy/#{first_page.last.event_id}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "first page, newest events descending" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      last_page  = events.reverse.drop(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{last_page.first.event_id}/forward/20"

      expect(parsed_body["links"]).to eq({
        "last"  => "http://www.example.com/res/streams/dummy/head/forward/20",
        "next"  => "http://www.example.com/res/streams/dummy/#{first_page.last.event_id}/backward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "last page, oldest events descending" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      last_page  = events.reverse.drop(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{first_page.last.event_id}/backward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/dummy/head/backward/20",
        "prev"  => "http://www.example.com/res/streams/dummy/#{last_page.first.event_id}/forward/20" ,
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "last page, oldest events descending" do
      events    = 40.times.map { DummyEvent.new }
      last_page = events.reverse.drop(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/head/forward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/dummy/head/backward/20",
        "prev"  => "http://www.example.com/res/streams/dummy/#{last_page.first.event_id}/forward/20",
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "non-edge page" do
      events = 41.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      next_page  = events.reverse.drop(20).take(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{first_page.last.event_id}/backward/20"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/dummy/head/backward/20",
        "last"  => "http://www.example.com/res/streams/dummy/head/forward/20",
        "next"  => "http://www.example.com/res/streams/dummy/#{next_page.last.event_id}/backward/20",
        "prev"  => "http://www.example.com/res/streams/dummy/#{next_page.first.event_id}/forward/20"
      })
      expect(parsed_body["data"].size).to eq(20)
    end

    specify "smaller than page size" do
      events = [DummyEvent.new, DummyEvent.new]
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy"

      expect(parsed_body["links"]).to eq({})
      expect(parsed_body["data"].size).to eq(2)
    end

    specify "custom page size" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(5)
      next_page  = events.reverse.drop(5).take(5)

      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{first_page.last.event_id}/backward/5"

      expect(parsed_body["links"]).to eq({
        "first" => "http://www.example.com/res/streams/dummy/head/backward/5",
        "last"  => "http://www.example.com/res/streams/dummy/head/forward/5",
        "next"  => "http://www.example.com/res/streams/dummy/#{next_page.last.event_id}/backward/5",
        "prev"  => "http://www.example.com/res/streams/dummy/#{next_page.first.event_id}/forward/5"
      })
      expect(parsed_body["data"].size).to eq(5)
    end

    specify "out of bounds beyond oldest" do
      events    = 40.times.map { DummyEvent.new }
      last_page = events.reverse.drop(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{last_page.last.event_id}/backward/20"

      expect(parsed_body["links"]).to eq({})
      expect(parsed_body["data"].size).to eq(0)
    end

    specify "out of bounds beyond newest" do
      events     = 40.times.map { DummyEvent.new }
      first_page = events.reverse.take(20)
      event_store.publish_events(events, stream_name: "dummy")
      get "/res/streams/dummy/#{first_page.first.event_id}/forward/20"

      expect(parsed_body["links"]).to eq({})
      expect(parsed_body["data"].size).to eq(0)
    end

    def dummy_event
      @dummy_event ||=
        DummyEvent.new(data: {
          foo: 1,
          bar: 2.0,
          baz: "3"
        })
    end

    def event_resource
      {
        "id" => dummy_event.event_id,
        "type" => "events",
        "attributes" => {
          "event_type" => "DummyEvent",
          "data" => {
            "foo" => 1,
            "bar" => 2.0,
            "baz" => "3"
          },
          "metadata" => {
            "timestamp" => dummy_event.metadata[:timestamp].as_json
          }
        }
      }
    end

    def all_stream_resource
      {
        "id" => "all",
        "type" => "streams"
      }
    end

    def dummy_stream_resource
      {
        "id" => "dummy",
        "type" => "streams"
      }
    end

    def event_store
      Rails.configuration.event_store
    end

    def parsed_body
      JSON.parse(response.body)
    end

    def get(url, headers: {}, params: {})
      headers["Content-Type"] = "application/vnd.api+json"

      if Gem::Version.new(Rails::VERSION::STRING) < Gem::Version.new("5.0.0")
        super(url, params, headers)
      else
        super(url, headers: headers, params: params)
      end
    end

    def app
      JsonApiLint.new(super)
    end
  end
end
