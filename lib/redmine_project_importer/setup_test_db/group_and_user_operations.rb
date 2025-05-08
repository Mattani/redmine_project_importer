module RedmineProjectImporter
  module SetupTestDb
    module GroupAndUserOperations
      def self.create_groups
        logger = RedmineProjectImporter.logger
        logger.info "Creating groups..."

        # FactoryBotのファクトリを明示的にロード
        FactoryBot.definition_file_paths = [File.expand_path('../../../spec/factories', __dir__)]
        FactoryBot.find_definitions

        # ロードされたファクトリを確認
        logger.debug "FactoryBot definition file paths: #{FactoryBot.definition_file_paths}"
        logger.debug "Loaded factories: #{FactoryBot.factories.map(&:name)}"

        groups = {
          development: FactoryBot.create(:group, name: "開発G"),
          sales: FactoryBot.create(:group, name: "営業G"),
          kaizen: FactoryBot.create(:group, name: "改善G"),
          management: FactoryBot.create(:group, name: "管理G")
        }
        logger.info "Groups created: #{groups.keys.join(', ')}"
        groups
      end

      def self.create_users(groups)
        logger = RedmineProjectImporter.logger
        logger.info "Creating users..."
        users = []
        group_memberships = Hash.new { |hash, key| hash[key] = [] }

        30.times do
          firstname = Faker::Name.first_name
          lastname = Faker::Name.last_name

          # 特殊文字を削除
          sanitized_firstname = firstname.downcase.gsub(/[^a-z0-9]/, '')
          sanitized_lastname = lastname.downcase.gsub(/[^a-z0-9]/, '')

          email = "#{sanitized_firstname}.#{sanitized_lastname}@example.com"
          login = "#{sanitized_firstname}_#{sanitized_lastname}"

          logger.info "  Creating user: #{firstname} #{lastname}, email: #{email}, login: #{login}"

          user = FactoryBot.create(:user, firstname: firstname, lastname: lastname, mail: email, login: login)
          users << user

          # ランダムにグループに追加
          if rand < 0.5
            group = groups.values.sample
            group.users << user
            group_memberships[group.name.to_sym] << user
          end
        end

        logger.info "Users created."
        { users: users, group_memberships: group_memberships }
      end
    end
  end
end