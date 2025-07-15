class SourceRole < ActiveRecord::Base
  self.table_name = 'roles'
  has_many :member_roles, foreign_key: 'role_id'
  has_many :members, through: :member_roles
end