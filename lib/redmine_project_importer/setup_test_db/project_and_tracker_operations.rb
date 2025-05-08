module RedmineProjectImporter
  module SetupTestDb
    module ProjectAndTrackerOperations
      def self.create_projects(users, groups, project_count = SAMPLE_PROJECTS.size)
        logger = RedmineProjectImporter.logger
        logger.info "Creating projects..."
        projects = []

        SAMPLE_PROJECTS.first(project_count).each_with_index do |project_data, index|
          project = FactoryBot.create(:project, project_index: index)

          # ID=1のユーザ(admin)をプロジェクトに追加
          admin_user = User.find_by(id: 1)
          if admin_user
            Member.create!(principal: admin_user, project: project, roles: [Role.find_by(name: '管理者')])
            logger.info "  Added admin user: #{admin_user.lastname} #{admin_user.firstname} to project: #{project.name}"
          else
            logger.warn "  Admin user (ID=1) not found. Skipping."
          end

          # 個人ユーザーをプロジェクトに追加
          users.sample(5).each do |user|
            Member.create!(principal: user, project: project, roles: [Role.find_by(name: '開発者')])
            logger.info "  Added user: #{user.lastname} #{user.firstname} to project: #{project.name}"
          end

          # グループをプロジェクトに追加
          Array(project_data[:group]).each do |group_key|
            group = groups[group_key.to_sym]
            if group
              Member.create!(principal: group, project: project, roles: [Role.find_by(name: '管理者')])
              logger.info "  Added group: #{group.name} to project: #{project.name}"
            else
              logger.warn "  Group with key '#{group_key}' not found. Skipping..."
            end
          end
          projects << project
        end

        logger.info "Projects created."
        projects
      end

      def self.add_sample_versions_to_project(project)
        logger = RedmineProjectImporter.logger
        logger.info "Adding sample versions to project: #{project.name}..."

        versions = []
        2.times do |i|
          version = FactoryBot.create(:version, project: project, name: "Version #{i + 1}")
          logger.info "  Added version: #{version.name} to project: #{project.name}"
          versions << version
        end

        logger.info "Sample versions added to project: #{project.name}."
        versions # 追加したバージョンを返却
      end

      def self.create_trackers
        logger = RedmineProjectImporter.logger
        logger.info "Creating trackers..."
        trackers = []

        3.times do |index|
          tracker = FactoryBot.create(:tracker, tracker_index: index)
          trackers << tracker
          logger.info "  Tracker: #{tracker.name}"
        end

        logger.info "Trackers created."
        trackers # 配列を返す
      end

      def self.assign_trackers_to_project(project, trackers)
        logger = RedmineProjectImporter.logger
        logger.info "Assigning trackers to project: #{project.name}..."

        trackers.each do |tracker|
          unless project.trackers.include?(tracker)
            project.trackers << tracker
            logger.info "  Added tracker '#{tracker.name}' to project '#{project.name}'"
          end
        end

        logger.info "Trackers assigned to project: #{project.name}."
      end
    end
  end
end