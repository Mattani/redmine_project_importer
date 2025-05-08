class SourceProjectsTracker < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'projects_trackers'
  # connects_to database: { reading: :import_source, writing: :import_source }

  belongs_to :project, foreign_key: 'project_id', class_name: 'SourceProject'
  belongs_to :tracker, foreign_key: 'tracker_id', class_name: 'SourceTracker'
end