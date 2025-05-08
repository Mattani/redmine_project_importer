class SourceUser < ActiveRecord::Base
  self.abstract_class = true
  self.table_name = 'users'
  self.inheritance_column = :_type_disabled  # STIを無効にする設定

  has_many :members, foreign_key: 'user_id', class_name: 'SourceMember'
  has_many :member_roles, through: :members, source: :member_roles

  # グループかどうかを判定
  scope :groups, -> { where(type: 'Group') }
  scope :users, -> { where(type: 'User') }
end
