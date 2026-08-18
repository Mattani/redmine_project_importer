class SourceWikiPage < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'wiki_pages'
end
