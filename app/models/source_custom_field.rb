class SourceCustomField < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'custom_fields'

  # STIを無効化
  self.inheritance_column = :_type_disabled

  has_many :custom_fields_projects, foreign_key: 'custom_field_id', class_name: 'SourceCustomFieldsProject'
  has_many :projects, through: :custom_fields_projects, source: :project

  has_many :source_custom_fields_trackers, foreign_key: 'custom_field_id', class_name: 'SourceCustomFieldsTracker'
  has_many :trackers, through: :source_custom_fields_trackers, source: :tracker
end