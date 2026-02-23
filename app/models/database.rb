class Database < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  has_many :db_rows, dependent: :destroy

  validates :name, presence: true
end
