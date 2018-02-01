require 'rubygems'
require 'nokogiri'
require 'open-uri'
require './statistics'
require './data'

class STS
  def initialize
    @verbose, @show_only_best, @print_results = false, false, false

    sts_disciplines = Data.sts_disciplines
    raise 'Error, no disciplines in sts_disciplines' if sts_disciplines.length.zero?

    if !ARGV.include?('--all') && !ARGV.include?('--only')
      disciplines = sts_disciplines.map {|k, _| k.to_s}
      puts "Parameters usage: [-v] [-s] [ --all | --only <DISCIPLINE_NAME> ]
        -s = --show-only-best\n-v = --verbose\nAvailable disciplines: #{disciplines}"
      exit
    end

    @verbose = true  if ARGV.include?('--verbose') or ARGV.include?('-v')
    @show_only_best = true if ARGV.include?('--show-only-best') or ARGV.include?('-s')

    sts_disciplines_to_parse = []
    sts_disciplines.each do |discipline_name, discipline_link|
      sts_disciplines_to_parse.push(discipline_link) if ARGV.include?('--all')
      sts_disciplines_to_parse.push(discipline_link) if ARGV.include?('--only') && discipline_name.to_s.include?(ARGV.last)
    end
    access_statistics(sts_disciplines_to_parse)
  end

  private
  def access_statistics(discipline_links)
    @discipline_statistics = []
    discipline_links.each do |discipline_website|
      website = Nokogiri::HTML(open(discipline_website))
      website.xpath("//*[@class='col2' or @class='col3']/tbody/tr/td[@class='stats']/a/@href").each do |statistic_website_link|
        @discipline_statistics.push(statistic_website_link.content)
      end
    end
    get_statistics
  end

  def get_statistics
    @discipline_statistics.each do |statistic_website_link|
      statistic_website = Nokogiri::HTML(open(statistic_website_link))

      @statistics = Statistics.new
      @statistics.last_meetings = []

      next unless statistic_website.at_css("//div[@class='row flex-items-xs-middle flex-items-xs-left']/div[@class='col-xs flex-xs-no-grow no-padding-right']")
      next unless statistic_website.at_css("//button.odds-disabled-content")

      @statistics.team1_name = statistic_website.css("//div[@class='row flex-items-xs-middle flex-items-xs-left']/div[@class='col-xs flex-xs-no-grow no-padding-right']").last.content
      @statistics.team2_name = statistic_website.css("//div[@class='row flex-items-xs-middle flex-items-xs-right']/div[@class='col-xs flex-xs-no-grow no-padding-left']").last.content
      @statistics.team1_abbr = statistic_website.css("//div[@class='row flex-items-xs-middle flex-items-xs-left']/div[@class='col-xs flex-xs-no-grow no-padding-right']").first.content
      @statistics.team2_abbr = statistic_website.css("//div[@class='row flex-items-xs-middle flex-items-xs-right']/div[@class='col-xs flex-xs-no-grow no-padding-left']").first.content
      @statistics.team1_odds = statistic_website.css("//button.odds-disabled-content").first.content
      @statistics.team2_odds = statistic_website.css("//button.odds-disabled-content").last.content
      @statistics.team1_form = statistic_website.css("//svg/switch/*/p")[0].content

      if statistic_website.css("//svg/switch/*/p")[4].content.include?('%')
        @statistics.team2_form = statistic_website.css("//svg/switch/*/p")[4].content
      else
        @statistics.team2_form = statistic_website.css("//svg/switch/*/p")[6].content
      end

      @statistics.draws = statistic_website.css("//svg/switch/*/p")[4].content
      @statistics.discipline_name = statistic_website.at_css("//div[@class='col-xs-12']/div[@class='row']/div[@class='col-xs-12 text-left']").content
      @statistics.team1_won = statistic_website.at_css("//div[@class='padding-medium text-center graphics-primary']/div[@class='h1 no-margin']/strong").content
      @statistics.team2_won = statistic_website.at_css("//div[@class='padding-medium text-center graphics-secondary']/div[@class='h1 no-margin']/strong").content

      statistic_website.xpath("//tr[td[contains(@class,'desktop-width-10')]]").each do |last_meeting|
        length =  last_meeting.css("td").length
        @statistics.last_meetings.push([
          last_meeting.css("td")[0].content, # date
          last_meeting.css("td")[length - 6].at_css("span").content, # team1_name
          last_meeting.css("td")[length - 4].at_css("div/span") ? last_meeting.css("td")[length - 4].css("div/span").first.content.to_i : -1, #team1_score
          last_meeting.css("td")[length - 4].at_css("div/span") ? last_meeting.css("td")[length - 4].css("div/span").last.content.to_i : -1, #team2_score
          last_meeting.css("td")[length - 2].at_css("span").content]) #team2_name
      end
      print_statistics
    end
  end

  def print_statistics
    meetings = Array.new
    meetings_full = String.new
    @statistics.last_meetings.each do |meeting|
      meetings_full += '| ' + meeting[0].slice(3, 10)
      if meeting[1] == @statistics.team1_name and meeting[2] > meeting[3]
        meetings.push(1)
        meetings_full += ' ' + @statistics.team1_abbr + ' (' + meeting[2].to_s + ':' + meeting[3].to_s + ') '
      elsif meeting[1] == @statistics.team1_name and meeting[2] < meeting[3]
        meetings.push(2)
        meetings_full += ' (' + meeting[2].to_s + ':' + meeting[3].to_s + ') ' + @statistics.team2_abbr + ' '
      elsif meeting[1] == @statistics.team2_name and meeting[2] > meeting[3]
        meetings.push(2)
        meetings_full += ' ' + @statistics.team2_abbr + ' (' + meeting[2].to_s + ':' + meeting[3].to_s + ') '
      elsif meeting[1] == @statistics.team2_name and meeting[2] < meeting[3]
        meetings.push(1)
        meetings_full += ' (' + meeting[2].to_s + ':' + meeting[3].to_s + ') ' + @statistics.team1_abbr + ' '
      elsif meeting[2] == meeting[3]
        meetings.push('X')
        meetings_full += ' (' + meeting[3].to_s + ':' + meeting[2].to_s + ') '
      end
    end

    team1_chances, team2_chances = 0.0, 0.0
    meetings.each_with_index do |meeting, i|
      # Higher priority for the two most recent meetings
      @priority = 4
      case meeting
      when 1
        if i > 1
          team1_chances += 1
        else
          team1_chances += @priority
        end
      when 2
        if i > 1
          team2_chances += 1
        else
          team2_chances += @priority
        end
      else nil
      end
    end
    team1_chances /= meetings.length + 8
    team2_chances /= meetings.length + 8
    team1_chances = (@statistics.team1_odds.to_f - 0.2) * team1_chances
    team2_chances = (@statistics.team2_odds.to_f - 0.2) * team2_chances
    if team1_chances < 1.0 or @statistics.team1_won < @statistics.team2_won then team1_chances = '-' else team1_chances = team1_chances.round(2) end
    if team2_chances < 1.0 or @statistics.team2_won < @statistics.team1_won then team2_chances = '-' else team2_chances = team2_chances.round(2) end

    if @show_only_best == false or (meetings[0] != 2 and meetings[1] != 2 and @statistics.team1_form >= @statistics.team2_form)
    # if @show_only_best == false or team1_chances != '-' or team2_chances != '-'
      puts '%-25.25s' % @statistics.team1_name + "\t" + @statistics.team1_odds + "\t" + @statistics.team1_form + "\t" + @statistics.team1_won + "\t" + meetings.join('') + "\t" + @statistics.discipline_name + "\t" + team1_chances.to_s + "\t" + team2_chances.to_s
      puts '%-25.25s' % @statistics.team2_name + "\t" + @statistics.team2_odds + "\t" + @statistics.team2_form + "\t" + @statistics.team2_won
      puts meetings_full + "\n" if @verbose
      puts "\n"
    end
  end
end
STS.new