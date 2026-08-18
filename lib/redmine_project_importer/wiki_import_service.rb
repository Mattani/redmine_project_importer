module RedmineProjectImporter
  class WikiImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      def import_wiki(context_mgr)
        source_project = context_mgr.source_project
        target_project = context_mgr.target_project

        source_wiki = fetch_source_wiki(source_project.id)
        unless source_wiki
          logger.info "  No wiki found for project: #{target_project.name}. Skipping wiki import."
          return
        end

        logger.info "  Importing wiki for project: #{target_project.name}"
        target_wiki = create_target_wiki(source_wiki, target_project)

        source_pages = fetch_source_wiki_pages(source_wiki.id)

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          source_pages.each do |source_page|
            new_page = copy_wiki_page(source_page, target_wiki)
            context_mgr.wiki_page_id_map[source_page.id] = new_page.id if new_page
          end
        end

        update_parent_wiki_page_relations(context_mgr, source_pages)
        import_wiki_contents(context_mgr, source_pages)
        import_wiki_redirects(context_mgr, source_wiki, target_wiki)

        logger.info "  Wiki import completed."
      end

      private

      def config_path
        File.expand_path('../../config/database.yml', __dir__)
      end

      def fetch_source_wiki(project_id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :import_source
        ) do
          SourceWiki.find_by(project_id: project_id)
        end
      end

      def create_target_wiki(source_wiki, target_project)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :primary
        ) do
          Wiki.create!(
            project_id: target_project.id,
            start_page: source_wiki.start_page,
            status: source_wiki.status
          )
        end
      end

      def fetch_source_wiki_pages(wiki_id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :import_source
        ) do
          SourceWikiPage.where(wiki_id: wiki_id).to_a
        end
      end

      # ページを1件コピーする。`parent_id`はこの時点では設定しない
      # （全ページ作成後、`update_parent_wiki_page_relations`で二段階目に解決する）。
      def copy_wiki_page(source_page, target_wiki)
        new_page = WikiPage.create!(
          wiki_id: target_wiki.id,
          title: source_page.title,
          protected: source_page.protected
        )

        # `created_on`をソースの値に上書きする（issue_import_serviceと同じパターン）
        sql = <<-SQL
          UPDATE wiki_pages
          SET created_on = #{ActiveRecord::Base.connection.quote(source_page.created_on)}
          WHERE id = #{new_page.id}
        SQL
        ActiveRecord::Base.connection.execute(sql)

        new_page
      rescue StandardError => e
        logger.error("Failed to copy wiki page ##{source_page.id} (#{source_page.title}): #{e.message}")
        nil
      end

      def update_parent_wiki_page_relations(context_mgr, source_pages)
        logger.info "  Updating parent-child wiki page relations..."
        wiki_page_id_map = context_mgr.wiki_page_id_map

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :primary
        ) do
          source_pages.each do |source_page|
            next unless source_page.parent_id

            child_target_id = wiki_page_id_map[source_page.id]
            parent_target_id = wiki_page_id_map[source_page.parent_id]

            if child_target_id && parent_target_id
              WikiPage.find(child_target_id).update!(parent_id: parent_target_id)
              logger.info "    Updated parent-child relation: Child Page ##{child_target_id} -> Parent Page ##{parent_target_id}"
            else
              logger.warn "    Skipping parent-child relation for Source Wiki Page ##{source_page.id}: Mapping not found."
            end
          end
        end

        logger.info "  Parent-child wiki page relations updated."
      end

      # `wiki_contents`(最新版1件)と`wiki_content_versions`(全履歴)をコピーする。
      # `WikiContent`は保存のたびに`after_save :create_version`で自動的に`WikiContentVersion`を
      # 作成してしまうため（`self.locking_column = 'version'`との衝突もある）、
      # 両テーブルともActiveRecordのモデル層を経由せず`exec_insert`で直接INSERTする。
      def import_wiki_contents(context_mgr, source_pages)
        logger.info "  Importing wiki contents..."
        wiki_page_id_map = context_mgr.wiki_page_id_map

        contents_by_page = fetch_wiki_contents_by_page(source_pages, wiki_page_id_map)

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :primary
        ) do
          contents_by_page.each do |source_page_id, data|
            target_page_id = wiki_page_id_map[source_page_id]
            source_content = data[:content]

            author_id = resolve_wiki_author_id(context_mgr, source_content.author_id, source_page_id)
            target_wiki_content_id = insert_wiki_content(target_page_id, author_id, source_content)
            next unless target_wiki_content_id

            data[:versions].each do |source_version|
              version_author_id = resolve_wiki_author_id(context_mgr, source_version.author_id, source_page_id)
              insert_wiki_content_version(target_wiki_content_id, target_page_id, version_author_id, source_version)
            end
          end
        end

        logger.info "  Wiki contents import completed."
      end

      def fetch_wiki_contents_by_page(source_pages, wiki_page_id_map)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :import_source
        ) do
          source_pages.each_with_object({}) do |source_page, acc|
            next unless wiki_page_id_map[source_page.id]

            source_content = SourceWikiContent.find_by(page_id: source_page.id)
            next unless source_content

            source_versions = SourceWikiContentVersion.where(wiki_content_id: source_content.id)
                                                        .order(:version).to_a
            acc[source_page.id] = { content: source_content, versions: source_versions }
          end
        end
      end

      # `members_mapping`（チケットのauthor解決と同じマッピング）でauthor_idを解決する。
      # 解決できない場合はanonymousにフォールバックし警告を記録する。
      def resolve_wiki_author_id(context_mgr, source_author_id, source_page_id)
        anonymous_id = User.anonymous.id
        return anonymous_id if source_author_id.nil? || source_author_id == anonymous_id

        members_mapping = context_mgr.mappings[:members_mapping]
        author_mapping = members_mapping[source_author_id]
        unless author_mapping
          context_mgr.add_warning({
            source_page_id: source_page_id,
            source_author_id: source_author_id,
            message: "Author for wiki page ##{source_page_id} is not mapped. Setting to Anonymous."
          })
          return anonymous_id
        end

        target_author_id = author_mapping[:target_user_id]
        unless User.exists?(id: target_author_id)
          context_mgr.add_warning({
            source_page_id: source_page_id,
            source_author_id: source_author_id,
            message: "Author for wiki page ##{source_page_id} not found in target DB. Setting to Anonymous."
          })
          return anonymous_id
        end

        target_author_id
      end

      def insert_wiki_content(target_page_id, author_id, source_content)
        sql = <<-SQL
          INSERT INTO wiki_contents (page_id, author_id, text, comments, updated_on, version)
          VALUES ($1, $2, $3, $4, $5, $6)
        SQL
        binds = [
          bind_attribute('page_id', target_page_id, ActiveRecord::Type::Integer.new),
          bind_attribute('author_id', author_id, ActiveRecord::Type::Integer.new),
          bind_attribute('text', source_content.text, ActiveRecord::Type::Text.new),
          bind_attribute('comments', source_content.comments, ActiveRecord::Type::String.new),
          bind_attribute('updated_on', source_content.updated_on, ActiveRecord::Type::DateTime.new),
          bind_attribute('version', source_content.version, ActiveRecord::Type::Integer.new)
        ]
        result = ActiveRecord::Base.connection.exec_insert(sql, 'SQL', binds)
        result.rows.first&.first
      rescue StandardError => e
        logger.error("Failed to insert wiki content for target page ##{target_page_id}: #{e.message}")
        nil
      end

      def insert_wiki_content_version(target_wiki_content_id, target_page_id, author_id, source_version)
        sql = <<-SQL
          INSERT INTO wiki_content_versions (wiki_content_id, page_id, author_id, data, compression, comments, updated_on, version)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        SQL
        binds = [
          bind_attribute('wiki_content_id', target_wiki_content_id, ActiveRecord::Type::Integer.new),
          bind_attribute('page_id', target_page_id, ActiveRecord::Type::Integer.new),
          bind_attribute('author_id', author_id, ActiveRecord::Type::Integer.new),
          bind_attribute('data', source_version.data, ActiveRecord::Type::Binary.new),
          bind_attribute('compression', source_version.compression, ActiveRecord::Type::String.new),
          bind_attribute('comments', source_version.comments, ActiveRecord::Type::String.new),
          bind_attribute('updated_on', source_version.updated_on, ActiveRecord::Type::DateTime.new),
          bind_attribute('version', source_version.version, ActiveRecord::Type::Integer.new)
        ]
        ActiveRecord::Base.connection.exec_insert(sql, 'SQL', binds)
      rescue StandardError => e
        logger.error("Failed to insert wiki content version ##{source_version.version} for target page ##{target_page_id}: #{e.message}")
        nil
      end

      def bind_attribute(name, value, type)
        ActiveRecord::Relation::QueryAttribute.new(name, value, type)
      end

      def import_wiki_redirects(context_mgr, source_wiki, target_wiki)
        logger.info "  Importing wiki redirects..."
        source_redirects = fetch_source_wiki_redirects(source_wiki.id)

        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :primary
        ) do
          source_redirects.each do |source_redirect|
            if source_redirect.redirects_to_wiki_id == source_wiki.id
              copy_wiki_redirect(source_redirect, target_wiki)
            else
              context_mgr.add_warning({
                source_wiki_id: source_wiki.id,
                source_redirect_title: source_redirect.title,
                message: "Wiki redirect '#{source_redirect.title}' points to another project's wiki " \
                         "(wiki_id: #{source_redirect.redirects_to_wiki_id}). Skipping."
              })
            end
          end
        end

        logger.info "  Wiki redirects import completed."
      end

      def fetch_source_wiki_redirects(wiki_id)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env, config_path: config_path, namespace: :import_source
        ) do
          SourceWikiRedirect.where(wiki_id: wiki_id).to_a
        end
      end

      def copy_wiki_redirect(source_redirect, target_wiki)
        new_redirect = WikiRedirect.create!(
          wiki_id: target_wiki.id,
          title: source_redirect.title,
          redirects_to: source_redirect.redirects_to,
          redirects_to_wiki_id: target_wiki.id
        )

        sql = <<-SQL
          UPDATE wiki_redirects
          SET created_on = #{ActiveRecord::Base.connection.quote(source_redirect.created_on)}
          WHERE id = #{new_redirect.id}
        SQL
        ActiveRecord::Base.connection.execute(sql)
      rescue StandardError => e
        logger.error("Failed to copy wiki redirect '#{source_redirect.title}': #{e.message}")
      end
    end
  end
end
