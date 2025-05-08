class SourceCustomFieldsProject < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'custom_fields_projects'
  self.inheritance_column = :_type_disabled  # STIを無効にする設定

  belongs_to :project, foreign_key: 'project_id', class_name: 'SourceProject'
  belongs_to :custom_field, foreign_key: 'custom_field_id', class_name: 'SourceCustomField'
end