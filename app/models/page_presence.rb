class PagePresence < ApplicationRecord
  belongs_to :workspace
  belongs_to :page
  belongs_to :user

  validates :session_token, presence: true, uniqueness: true
  validates :last_seen_at, presence: true

  scope :for_page, ->(page_id) { where(page_id: page_id) }
  scope :active_since, ->(timestamp) { where(arel_table[:last_seen_at].gteq(timestamp)) }
  scope :editing_active_since, lambda { |timestamp|
    where.not(editing_block_id: nil).where(arel_table[:editing_seen_at].gteq(timestamp))
  }
end
