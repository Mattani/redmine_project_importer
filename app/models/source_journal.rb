class SourceJournal < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'journals'
end