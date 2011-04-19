require 'date'

class Sprint < Version
    unloadable

    validate :start_and_end_dates

    named_scope :open_sprints, lambda { |project|
        {
            :order => 'sprint_start_date ASC, effective_date ASC',
            :conditions => [ "versions.status = 'open' and versions.project_id = ?", project.id ]
        }
    }

    named_scope :order_by_date, :order => 'sprint_start_date ASC, effective_date ASC'
    named_scope :order_by_name, :order => "#{Version.table_name}.name ASC"

    named_scope :apply_to, lambda { |project| {:include => :project,
                                               :conditions => ["#{Version.table_name}.project_id = #{project.id}" +
                                               " OR (#{Project.table_name}.status = #{Project::STATUS_ACTIVE} AND (" +
                                               " #{Version.table_name}.sharing = 'system'" +
                                               " OR (#{Project.table_name}.lft >= #{project.root.lft} AND #{Project.table_name}.rgt <= #{project.root.rgt} AND #{Version.table_name}.sharing = 'tree')" +
                                               " OR (#{Project.table_name}.lft < #{project.lft} AND #{Project.table_name}.rgt > #{project.rgt} AND #{Version.table_name}.sharing IN ('hierarchy', 'descendants'))" +
                                               " OR (#{Project.table_name}.lft > #{project.lft} AND #{Project.table_name}.rgt < #{project.rgt} AND #{Version.table_name}.sharing = 'hierarchy')" +
                                               "))"]}}

    named_scope :displayed_left, lambda { |project| { :joins => sanitize_sql_array(["LEFT OUTER JOIN (SELECT * from #{VersionSetting.table_name}" +
                                                                                    " WHERE project_id = ? ) version_settings" +
                                                                                    " ON version_settings.version_id = versions.id",
                                                                                    project.id]),
                                                      :conditions => ["(version_settings.project_id = ? AND version_settings.display = ?)" +
                                                                      " OR (version_settings.project_id is NULL)",
                                                                      project.id, VersionSetting::DISPLAY_LEFT] } }

    named_scope :displayed_right, lambda { |project| { :include => :version_settings,
                                                      :conditions => ["version_settings.project_id = ? AND version_settings.display = ?",
                                                                      project.id, VersionSetting::DISPLAY_RIGHT] } }



    def stories(project, options = {} )
        Story.sprint_backlog(project, self, options)
    end

    def points
        return stories.inject(0){|sum, story| sum + story.story_points.to_i}
    end

    def has_wiki_page
        return false if wiki_page_title.blank?

        page = project.wiki.find_page(self.wiki_page_title)
        return false if !page

        template = project.wiki.find_page(Setting.plugin_redmine_backlogs[:wiki_template])
        return false if template && page.text == template.text

        return true
    end

    def wiki_page
        if ! project.wiki
            return ''
        end

        self.update_attribute(:wiki_page_title, Wiki.titleize(self.name)) if wiki_page_title.blank?

        page = project.wiki.find_page(self.wiki_page_title)
        template = project.wiki.find_page(Setting.plugin_redmine_backlogs[:wiki_template])

        if template and not page
            page = WikiPage.new(:wiki => project.wiki, :title => self.wiki_page_title)
            page.content = WikiContent.new
            page.content.text = "h1. #{self.name}\n\n#{template.text}"
            page.save!
        end

        return wiki_page_title
    end

    def days(cutoff = nil, alldays = false)
        # assumes mon-fri are working days, sat-sun are not. this
        # assumption is not globally right, we need to make this configurable.
        cutoff = self.effective_date if cutoff.nil?
        return (self.sprint_start_date .. cutoff).select {|d| alldays || (d.wday > 0 and d.wday < 6) }
    end

    def eta
        return nil if ! self.start_date

        dpp = self.project.scrum_statistics.info[:average_days_per_point]
        return nil if !dpp

        # assume 5 out of 7 are working days
        return self.start_date + Integer(self.points * dpp * 7.0/5)
    end

    def has_burndown?
      !!(self.effective_date and self.sprint_start_date)
    end

    def activity
        bd = self.burndown('up')
        return false if !bd

        # assume a sprint is active if it's only 2 days old
        return true if bd.remaining_hours.size <= 2

        return Issue.exists?(['fixed_version_id = ? and ((updated_on between ? and ?) or (created_on between ? and ?))', self.id, -2.days.from_now, Time.now, -2.days.from_now, Time.now])
    end

    def burndown(project, burn_direction = nil)
        return nil if not self.has_burndown?
        @cached_burndown ||= Burndown.new(self, project, burn_direction)
        return @cached_burndown
    end

    def self.generate_burndown(only_current = true)
        if only_current
            conditions = ["? between sprint_start_date and effective_date", Date.today]
        else
            conditions = "1 = 1"
        end

        Version.find(:all, :conditions => conditions).each { |sprint|
            sprint.burndown
        }
    end

    def impediments(project)
      Impediment.find(:all, :conditions => {:fixed_version_id => self, :project_id => project})
    end

    private
    def start_and_end_dates
        errors.add_to_base("Sprint cannot end before it starts") if self.effective_date && self.sprint_start_date && self.sprint_start_date >= self.effective_date
    end

end
