class SourceWiki < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'wikis'
end
