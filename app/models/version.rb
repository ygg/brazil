require 'rio'

require 'brazil/schema_revision'
require 'brazil/version_control'

class Version < ActiveRecord::Base
  STATE_CREATED = 'created'
  STATE_TESTED = 'tested'
  STATE_DEPLOYED = 'deployed'

  belongs_to :activity

  has_many :db_instance_version
  has_many :db_instances, :through => :db_instance_version

  validates_presence_of :schema, :update_sql, :rollback_sql, :schema_version
  validates_inclusion_of :create_schema_version, :in => [true, false]

  before_save :check_no_duplicate_schema_db, :update_activity_state

  def version_control_sql(generate_update_sql, generate_rollback_sql, vc_username, vc_password)
    begin
      version_repos_path = "#{::AppConfig.vc_uri}/#{activity.app.vc_path}"
      vc = Brazil::VersionControl.new(::AppConfig.vc_type, version_repos_path, vc_username, vc_password)

      version_working_copy = rio(::AppConfig.vc_dir, activity.app.vc_path)
      if version_working_copy.directory?
        vc.update(version_working_copy.path)
      else
        vc.checkout(version_working_copy.path)
      end

      if schema_version.to_s.empty?
        vc_schema_version = '1_0_0'
      else
        vc_schema_version = schema_version
      end

      version_sql_dir = rio(version_working_copy, schema, db_instance_test.db_type.downcase).mkpath
      version_update_sql = rio(version_sql_dir, "#{schema}-#{vc_schema_version}-update.sql").mode("w+")
      version_rollback_sql = rio(version_sql_dir, "#{schema}-#{vc_schema_version}-rollback.sql").mode("w+")

      version_update_sql.print!(generate_update_sql.call)
      version_rollback_sql.print!(generate_rollback_sql.call)

      vc.add(rio(version_working_copy, schema).path)
      vc.commit(version_working_copy.path, "TOOL Add version #{schema_version} SQL for #{activity.app.name} schema #{schema}")

      return true
    rescue Brazil::VersionControlException => vc_exception
      return false
    end
  end

  def init_schema_version(db_username, db_password)
    begin
      next_schema_version = db_instance_test.find_next_schema_version(db_username, db_password, schema)
    rescue Brazil::DBException => exception
      errors.add_to_base("Could not lookup version for schema '#{schema}' (#{exception})")
      return
    end

    if schema_version
      self.schema_version = next_schema_version
      self.create_schema_version = false
    else
      self.schema_version = '1_0_0'
      self.create_schema_version = true
    end
  end

  def update_schema_version(updated_schema_version, db_username, db_password)
    begin
      next_schema_version = db_instance_test.find_next_schema_version(db_username, db_password, schema)
    rescue Brazil::DBException => exception
      errors.add_to_base("Could not lookup version for schema '#{schema}' (#{exception})")
      return
    end

    if next_schema_version
      self.create_schema_version = false
      next_schema_revision = Brazil::SchemaRevision.from_string(next_schema_version)
    else
      self.create_schema_version = true
      next_schema_revision = Brazil::SchemaRevision.new(1, 0, 0)
    end

    updated_schema_revision = Brazil::SchemaRevision.from_string(updated_schema_version)
    if updated_schema_revision >= next_schema_revision
      self.schema_version = updated_schema_version
    else
      errors.add_to_base("Updated schema version: #{updated_schema_revision}, can not be less than the next schema version: #{next_schema_revision}")
    end
  end

  def db_instance_test
    test_db_instance = DbInstance.find_all_by_id(db_instance_ids, :conditions => {:db_env => DbInstance::ENV_TEST}).first
    if test_db_instance
      test_db_instance
    else
      raise Brazil::NoDBInstanceException, "Please select a Test Database for Version"
    end
  end

  def schema_revision
    if schema_version
      Brazil::SchemaRevision.from_string(schema_version)
    else
      nil
    end
  end

  def created?
    (state == STATE_CREATED)
  end

  def tested?
    (state == STATE_TESTED)
  end

  def deployed?
    (state == STATE_DEPLOYED)
  end

  def states
    [STATE_CREATED, STATE_TESTED, STATE_DEPLOYED]
  end

  def to_s
    "#{schema}@#{db_instance_test}"
  end

  private

  def check_no_duplicate_schema_db
    match = DbInstanceVersion.find(:first, :joins => [:version, :db_instance], :conditions => ['versions.schema = ? AND db_instances.id = ? AND versions.activity_id = ?', schema, db_instance_test.id, activity.id])
    if match && match.version_id != id
      errors.add_to_base("Creating a second Version with the same Schema '#{schema}' and Test Database '#{db_instance_test}' is not allowed")
      false
    end
  end

  def update_activity_state
    if activity.development?
      activity.versioned!
    end
  end
end
