require 'activerecord-import'

module RailsEventStoreActiveRecord
  class EventRepository
    InvalidDatabaseSchema = Class.new(StandardError)

    POSITION_SHIFT = 1

    def initialize(mapper: RubyEventStore::Mappers::Default.new)
      verify_correct_schema_present
      @mapper      = mapper
      @repo_reader = EventRepositoryReader.new(mapper)
    end

    def append_to_stream(events, stream_name, expected_version)
      add_to_stream(events, stream_name, expected_version, true) do |event|
        build_event_record(event).save!
        event.event_id
      end
    end

    def link_to_stream(event_ids, stream_name, expected_version)
      (normalize_to_array(event_ids) - Event.where(id: event_ids).pluck(:id)).each do |id|
        raise RubyEventStore::EventNotFound.new(id)
      end
      add_to_stream(event_ids, stream_name, expected_version, nil) do |event_id|
        event_id
      end
    end

    def delete_stream(stream_name)
      EventInStream.where(stream: stream_name).delete_all
    end

    def has_event?(event_id)
      @repo_reader.has_event?(event_id)
    end

    def last_stream_event(stream_name)
      @repo_reader.last_stream_event(stream_name)
    end

    def read_events_forward(stream_name, after_event_id, count)
      @repo_reader.read_events_forward(stream_name, after_event_id, count)
    end

    def read_events_backward(stream_name, before_event_id, count)
      @repo_reader.read_events_backward(stream_name, before_event_id, count)
    end

    def read_stream_events_forward(stream_name)
      @repo_reader.read_stream_events_forward(stream_name)
    end

    def read_stream_events_backward(stream_name)
      @repo_reader.read_stream_events_backward(stream_name)
    end

    def read_all_streams_forward(after_event_id, count)
      @repo_reader.read_all_streams_forward(after_event_id, count)
    end

    def read_all_streams_backward(before_event_id, count)
      @repo_reader.read_all_streams_backward(before_event_id, count)
    end

    def read_event(event_id)
      @repo_reader.read_event(event_id)
    end

    def get_all_streams
      @repo_reader.get_all_streams
    end

    private

    attr_reader :mapper

    def add_to_stream(collection, stream_name, expected_version, include_global, &to_event_id)
      raise RubyEventStore::InvalidExpectedVersion if stream_name.eql?(RubyEventStore::GLOBAL_STREAM) && !expected_version.equal?(:any)

      collection = normalize_to_array(collection)
      expected_version = normalize_expected_version(expected_version, stream_name)

      ActiveRecord::Base.transaction(requires_new: true) do
        in_stream = collection.flat_map.with_index do |element, index|
          position = compute_position(expected_version, index)
          event_id = to_event_id.call(element)
          collection = []
          collection.unshift({
            stream: RubyEventStore::GLOBAL_STREAM,
            position: nil,
            event_id: event_id
          }) if include_global
          collection.unshift({
            stream:   stream_name,
            position: position,
            event_id: event_id
          }) unless stream_name.eql?(RubyEventStore::GLOBAL_STREAM)
          collection
        end
        EventInStream.import(in_stream)
      end
      self
    rescue ActiveRecord::RecordNotUnique => e
      raise_error(e)
    end

    def raise_error(e)
      if detect_index_violated(e)
        raise RubyEventStore::EventDuplicatedInStream
      end
      raise RubyEventStore::WrongExpectedEventVersion
    end

    def compute_position(expected_version, index)
      unless expected_version.equal?(:any)
        expected_version + index + POSITION_SHIFT
      end
    end

    def normalize_expected_version(expected_version, stream_name)
      case expected_version
        when Integer, :any
          expected_version
        when :none
          -1
        when :auto
          eis = EventInStream.where(stream: stream_name).order("position DESC").first
          (eis && eis.position) || -1
        else
          raise RubyEventStore::InvalidExpectedVersion
      end
    end

    MYSQL_PKEY_ERROR    = "for key 'PRIMARY'"
    POSTGRES_PKEY_ERROR = "event_store_events_pkey"
    SQLITE3_PKEY_ERROR  = "event_store_events.id"

    MYSQL_INDEX_ERROR    = "for key 'index_event_store_events_in_streams_on_stream_and_event_id'"
    POSTGRES_INDEX_ERROR = "Key (stream, event_id)"
    SQLITE3_INDEX_ERROR  = "event_store_events_in_streams.stream, event_store_events_in_streams.event_id"

    def detect_index_violated(e)
      m = e.message
      m.include?(MYSQL_PKEY_ERROR)     ||
      m.include?(POSTGRES_PKEY_ERROR)  ||
      m.include?(SQLITE3_PKEY_ERROR)   ||

      m.include?(MYSQL_INDEX_ERROR)    ||
      m.include?(POSTGRES_INDEX_ERROR) ||
      m.include?(SQLITE3_INDEX_ERROR)
    end

    def build_event_record(event)
      serialized_record = mapper.event_to_serialized_record(event)
      Event.new(
        id:         serialized_record.event_id,
        data:       serialized_record.data,
        metadata:   serialized_record.metadata,
        event_type: serialized_record.event_type
      )
    end

    def normalize_to_array(events)
      [*events]
    end

    def incorrect_schema_message
      <<-MESSAGE
Oh no!

It seems you're using RailsEventStoreActiveRecord::EventRepository
with incompaible database schema.

We've redesigned database structure in order to fix several concurrency-related
bugs. This repository is intended to work on that improved data layout.

We've prepared migration that would take you from old schema to new one.
This migration must be run offline -- take that into consideration:

  rails g rails_event_store_active_record:v1_v2_migration
  rake db:migrate


If you cannot migrate right now -- you can for some time continue using
old repository. In order to do so, change configuration accordingly:

  config.event_store = RailsEventStore::Client.new(
                         repository: RailsEventStoreActiveRecord::LegacyEventRepository.new
                       )


      MESSAGE
    end

    def verify_correct_schema_present
      return unless ActiveRecord::Base.connected?
      legacy_columns  = ["id", "stream", "event_type", "event_id", "metadata", "data", "created_at"]
      current_columns = ActiveRecord::Base.connection.columns("event_store_events").map(&:name)
      raise InvalidDatabaseSchema.new(incorrect_schema_message) if legacy_columns.eql?(current_columns)
    end
  end

end
