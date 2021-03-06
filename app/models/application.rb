require 'applications/importer'
require 'simple_statistics'

class Application < ActiveRecord::Base
  class << self
    def import(data)
      Applications::Importer.new(self, data).run
    end

    def visible
      where(hidden: false)
    end

    def sort_by(column)
      column = column.to_sym
      sorted = if [:mean, :median, :weighted, :truncated].include?(column)
        all.sort_by { |application| application.total_rating(column) }.reverse
      else
        column == :id ? order(column) : all.sort_by(&column)
      end
      sorted
    end
  end

  attr_accessible :timestamp, :data, :hidden, :sponsor_pick, :country, :min_living, :project_visibility, :project_name, :comment

  serialize :data

  has_many :ratings, -> { order(user_name: :asc) } do
    def excluding(names)
      where('user_name NOT IN (?)', names)
    end
  end
  has_many :comments

  # def prev
  #   self.class.where('id < ?', id).visible.order(:id).last
  # end

  # def next
  #   self.class.where('id > ?', id).visible.order(:id).first
  # end

  def student_name
    data.values[1]
  end

  def total_rating(type)
    total = calc_rating(type)
    total += SPONSOR_PICK if sponsor_pick?
    total += project_visibility.to_i unless project_visibility.blank?
    total
  end

  def calc_rating(type)
    types = { truncated: :mean, weighted: :wma }
    values = ratings.map(&:value).sort
    values.shift && values.pop if type == :truncated
    values.size > 0 ? values.send(types[type] || type).round_to(1) : 0
  rescue
    -1 # wma seems to have issues with less than 2 values
  end

  def rating_defaults
    keys = [:women_priority, :skill_level, :practice_time, :project_time, :support]
    keys.inject({}) { |defaults, key| defaults.merge(key => send("estimated_#{key}")) }
  end

  def sponsor_pick?
    sponsor_pick.present?
  end

  def estimated_women_priority
    5 + (seems_to_have_pair? ? 5 : 0)
  end

  def estimated_skill_level
    if seems_to_have_pair?
      values = [student_skill_level, pair_skill_level].sort
      ((values.first.to_f + values.last.to_f * 2) / 3).round
    else
    end
  end

  def estimated_practice_time
    if seems_to_have_pair?
      [student_practice_time.to_i, pair_practice_time.to_i].max
    else
      student_practice_time
    end
  end

  def estimated_project_time
    10
  end

  def estimated_support
    value = data['Coach(es): How much time can your coaches put into (being available for) support, in total?']
    return unless value =~ /^\d+$/
    value = value.to_i
    case true
      when value >= 5 then 8
      when value >= 3 then 5
      when value >= 1 then 1
    end
  end

  def seems_to_have_pair?
    !!pair_skill_level
  end

  def student_skill_level
    data['What level of coding do you see yourself in Ruby/Rails?'].try(:to_i)
  end

  def pair_skill_level
    data['What level of coding does your pair have?'].try(:to_i)
  end

  PRACTICE_TIME = {
    'Between 1 and 3 months'  => 2,
    'Between 3 and 6 months'  => 4,
    'Between 6 and 9 months'  => 6,
    'Between 9 and 12 months' => 8,
    'More that 12 months'     => 10
  }

  def student_practice_time
    PRACTICE_TIME[data['For how many months have you actively been learning after your first workshop?']]
  end

  def pair_practice_time
    PRACTICE_TIME[data['For how many months has your pair actively been learning after her first workshop?']]
  end

  # def filtered_data
  #   data.dup.delete_if { |key, value| key =~ /Student/ }
  # end
end
