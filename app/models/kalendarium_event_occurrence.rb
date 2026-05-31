require "delegate"

class KalendariumEventOccurrence < SimpleDelegator
  attr_reader :source_event, :starts_at_utc, :ends_at_utc, :occurrence_key

  def initialize(source_event:, starts_at_utc:, ends_at_utc:, occurrence_key:)
    @source_event = source_event
    @starts_at_utc = starts_at_utc
    @ends_at_utc = ends_at_utc
    @occurrence_key = occurrence_key
    super(source_event)
  end

  def id
    source_event.id
  end

  def to_model
    source_event
  end

  def to_key
    source_event.to_key
  end

  def persisted?
    source_event.persisted?
  end

  def model_name
    source_event.class.model_name
  end

  def occurrence_dom_id
    "kalendarium_event_#{source_event.id}_#{occurrence_key}"
  end
end
