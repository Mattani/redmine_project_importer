class SourceCustomFieldsTracker < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'custom_fields_trackers'
  # connects_to database: { reading: :import_source, writing: :import_source }

  belongs_to :source_custom_field, foreign_key: 'custom_field_id', class_name: 'SourceCustomField'
  belongs_to :tracker, foreign_key: 'tracker_id', class_name: 'SourceTracker'
end