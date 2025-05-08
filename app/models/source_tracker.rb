class SourceTracker < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'trackers'

  has_many :source_custom_fields_trackers, foreign_key: 'tracker_id', class_name: 'SourceCustomFieldsTracker'
  has_many :source_custom_fields, through: :source_custom_fields_trackers, source: :source_custom_field
end