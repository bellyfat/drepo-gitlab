# lib/tasks/db_enhancements.rake

####### Important information ####################
# This file is used to setup a shared extensions #
# within a dedicated schema. This gives us the   #
# advantage of only needing to enable extensions #
# in one place.                                  #
#                                                #
# This task should be run AFTER db:create but    #
# BEFORE db:migrate.                             #
##################################################

namespace :db do
  namespace :drepo do
    desc 'Also create shared_extensions Schema'
    task create_extensions: :environment do
      $stdout.puts "Create shared_extensions schema"
      # Create Schema
      ActiveRecord::Base.connection.execute 'CREATE SCHEMA IF NOT EXISTS shared_extensions;'
      # Enable UUID-OSSP
      ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA shared_extensions;'
      ActiveRecord::Base.connection.execute 'ALTER EXTENSION "uuid-ossp" SET SCHEMA shared_extensions;'
      # Enable pg_trgm
      ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS "pg_trgm" SCHEMA shared_extensions;'
      ActiveRecord::Base.connection.execute 'ALTER EXTENSION "pg_trgm" SET SCHEMA shared_extensions;'
      # Grant usage to public
      ActiveRecord::Base.connection.execute 'GRANT usage ON SCHEMA shared_extensions to public;'

      $stdout.puts "Set database default search_path"
      config = ActiveRecord::Base.connection_config
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute "ALTER DATABASE #{config[:database]} set search_path = #{config[:schema_search_path] || 'public,shared_extensions'};"
      end
    end

    desc 'Create multiple schemas'
    task create_schemas: :environment do
      $stdout.puts "Create drepo project schema"
      # Create drepo_project schema
      Apartment::Tenant.create 'drepo_project_pending' unless schema_present?('drepo_project_pending')
      Apartment::Tenant.create 'drepo_project_completed' unless schema_present?('drepo_project_completed')
    end

    desc 'Add drepo extend columns and triggers'
    task extend_columns_triggers: :environment do
      $stdout.puts "Add extend columns to drepo project tables, and create triggers"
      # public schema add drepo_username column to user_shared_tables
      add_drepo_username_column 'public'

      # public schema add drepo_updated_at column
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE public.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_uuid UUID DEFAULT uuid_generate_v4() NOT NULL;' ||
              'ALTER TABLE public.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_updated_at timestamp without time zone DEFAULT now();' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_drepo_uuid ON public.' || T.myTable || ' USING btree (drepo_uuid);' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_drepo_updated_at ON public.' || T.myTable || ' USING btree (drepo_updated_at);' as script
           from
              (
                SELECT DISTINCT table_name as myTable FROM information_schema.tables WHERE table_schema='public' AND table_name IN (#{enhance_tables})
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end

      # add function
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        create or replace function shared_extensions.func_drepo_touch() returns trigger as $$
          begin
            NEW.drepo_updated_at := NOW();
            return NEW;
          end;
        $$ language plpgsql;
      })
      end

      # add trigger to every table
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
           r record;
        begin
        for r in
           select
              'DROP TRIGGER IF EXISTS trig_drepo_touch on "public"."' || T.myTable || '";'
              'CREATE TRIGGER trig_drepo_touch BEFORE INSERT OR UPDATE ON public.' || T.myTable || ' FOR EACH ROW EXECUTE PROCEDURE shared_extensions.func_drepo_touch()' as script
           from
              (
                SELECT DISTINCT table_name as myTable FROM information_schema.columns WHERE table_schema='public' AND column_name='drepo_updated_at' AND table_name IN (#{enhance_tables})
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end

      # drepo_project schema add extend columns
      add_drepo_username_column 'drepo_project_pending'
      add_drepo_username_column 'drepo_project_completed'
      add_extend_columns 'drepo_project_pending'
      add_extend_columns 'drepo_project_completed'
    end

    desc 'Remove foreign keys'
    task remove_foreign_keys: :environment do
      $stdout.puts "Remove foreign keys in pending and completed schemas"

      # remove foreign keys point to users table
      remove_fk_by_foreign_table('drepo_project_pending', 'users')
      remove_fk_by_foreign_table('drepo_project_completed', 'users')

      # remove foreign keys of table column
      remove_fk_by_column('drepo_project_pending', 'merge_requests', 'head_pipeline_id')
      remove_fk_by_column('drepo_project_completed', 'merge_requests', 'head_pipeline_id')
      remove_fk_by_column('drepo_project_pending', 'merge_requests', 'latest_merge_request_diff_id')
      remove_fk_by_column('drepo_project_completed', 'merge_requests', 'latest_merge_request_diff_id')
      remove_fk_by_column('drepo_project_pending', 'merge_request_metrics', 'pipeline_id')
      remove_fk_by_column('drepo_project_completed', 'merge_request_metrics', 'pipeline_id')
    end

    def remove_fk_by_foreign_table(schema, foreign_table)
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE ' || T.myTableSchema || '.' || T.myTableName || ' DROP CONSTRAINT IF EXISTS '|| T.myConstraintName
              as script
            from
              (
                SELECT tc.constraint_name as myConstraintName, ccu.table_schema as myTableSchema, tc.table_name as myTableName
                FROM
                  information_schema.table_constraints AS tc
                  JOIN information_schema.key_column_usage AS kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                  JOIN information_schema.constraint_column_usage AS ccu
                    ON ccu.constraint_name = tc.constraint_name
                    AND ccu.table_schema = tc.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND ccu.table_name = '#{foreign_table}'
                  AND ccu.table_schema = '#{schema}'
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end
    end

    def remove_fk_by_column(schema, table, column)
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE ' || T.myTableSchema || '.' || T.myTableName || ' DROP CONSTRAINT IF EXISTS '|| T.myConstraintName
              as script
            from
              (
                SELECT tc.constraint_name as myConstraintName, ccu.table_schema as myTableSchema, tc.table_name as myTableName
                FROM
                  information_schema.table_constraints AS tc
                  JOIN information_schema.key_column_usage AS kcu
                    ON tc.constraint_name = kcu.constraint_name
                    AND tc.table_schema = kcu.table_schema
                  JOIN information_schema.constraint_column_usage AS ccu
                    ON ccu.constraint_name = tc.constraint_name
                    AND ccu.table_schema = tc.table_schema
                WHERE tc.constraint_type = 'FOREIGN KEY'
                  AND tc.table_name = '#{table}'
                  AND kcu.column_name = '#{column}'
                  AND ccu.table_schema = '#{schema}'
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end
    end

    def add_extend_columns(schema)
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_uuid UUID NOT NULL;' ||
              'ALTER TABLE #{schema}.' || T.myTable || ' ALTER COLUMN drepo_uuid DROP DEFAULT;' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_drepo_uuid ON #{schema}.' || T.myTable || ' USING btree (drepo_uuid);' ||
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_updated_at timestamp without time zone;' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_drepo_updated_at ON #{schema}.' || T.myTable || ' USING btree (drepo_updated_at);' ||
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS original_updated_at timestamp without time zone;' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_original_updated_at ON #{schema}.' || T.myTable || ' USING btree (original_updated_at);' ||
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS original_created_at timestamp without time zone;' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_original_created_at ON #{schema}.' || T.myTable || ' USING btree (original_created_at);'
              as script
           from
              (
                SELECT DISTINCT table_name as myTable FROM information_schema.tables WHERE table_schema='public' AND table_name IN (#{enhance_tables})
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })

        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_id integer NOT NULL;' ||
              'CREATE INDEX IF NOT EXISTS index_' || T.myTable || '_on_drepo_id ON #{schema}.' || T.myTable || ' USING btree (drepo_id);'
              as script
           from
              (
                SELECT DISTINCT table_name as myTable FROM information_schema.tables WHERE table_schema='public' AND table_name IN (#{enhance_tables})
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end
    end

    def add_drepo_username_column(schema)
      ActiveRecord::Base.connection_pool.with_connection do |conn|
        conn.execute(%Q{
        do $$
        declare
            r record;
        begin
        for r in
            select
              'ALTER TABLE #{schema}.' || T.myTable || ' ADD COLUMN IF NOT EXISTS drepo_username character varying;'
              as script
           from
              (
                SELECT DISTINCT table_name as myTable FROM information_schema.tables WHERE table_schema='public' AND table_name IN (#{user_shared_tables})
              ) t
        loop
        execute r.script;
        end loop;
        end;
        $$;
      })
      end
    end

    def user_shared_tables
      Dg::ProjectSnapshot::USER_SHARED_TABLE_COLUMNS.keys.map { |t| ActiveRecord::Base.connection.quote(t) }.join(',')
    end

    def enhance_tables
      Dg::ProjectSnapshot::ENHANCE_TABLES.map { |t| ActiveRecord::Base.connection.quote(t) }.join(',')
    end

    def schema_present?(schema)
      sql = 'select schema_name from information_schema.schemata;'
      ActiveRecord::Base.connection.query(sql).flatten.include? schema
    end

    desc 'Initialize drepo schema'
    task init: :environment do
      Rake::Task["db:drepo:create_extensions"].invoke
      Rake::Task["db:drepo:create_schemas"].invoke
      Rake::Task["db:drepo:extend_columns_triggers"].invoke
      Rake::Task["db:drepo:remove_foreign_keys"].invoke
    end
  end
end

%w(db:create db:test:purge).each do |task|
  Rake::Task[task].enhance do
    Rake::Task["db:drepo:create_extensions"].invoke
    Rake::Task["db:drepo:create_schemas"].invoke
  end
end
#
# %w(db:schema:load db:structure:load db:test:load_schema db:test:load_structure).each do |task|
#   Rake::Task[task].enhance do
#     Rake::Task["db:drepo:create_extensions"].invoke
#     Rake::Task["db:drepo:create_schemas"].invoke
#     Rake::Task["db:drepo:extend_columns_triggers"].invoke
#   end
# end
#
# Rake::Task["db:migrate"].enhance do
#   Rake::Task["db:drepo:extend_columns_triggers"].invoke
# end
