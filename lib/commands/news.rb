require 'time_difference'
require 'iso-639'

module Visjar
  module Commands
    class News
      def self.run(client, slack, recast)
        recast = recast['sentences'].first

        # Get informations about the request
        @nationality = recast['entities']['nationality'].first['value'] rescue nil
        if @nationality
          loc     = ISO_639.find_by_english_name(@nationality.capitalize)
          locale = loc.any? ? loc[2] : Config.locale
        else
          locale = Config.locale
        end

        response = JSON.parse(HTTParty.get("http://ajax.googleapis.com/ajax/services/feed/load?v=1.0&num=#{Config.limit_news}&q=https%3A%2F%2Fnews.google.com%2Fnews%3Fned%3D#{locale}%26output%3Drss").body)

        if response['responseStatus'] == 200
          news = response['responseData']['feed']
          news['entries'].each do |entry|
            date  = stringify(TimeDifference.between(Time.parse(entry['publishedDate']), Time.now).in_general)
            link  = entry['link'][entry['link'].rindex("&url=")+5..-1]
            title = entry['title'][0..entry['title'].rindex(" - ")-1]

            client.send_message(slack['channel'], "<#{link}|#{title}> - _#{date}_", {unfurl_links: false, unfurl_media: false})
          end
        else
          client.send_message(slack['channel'], "Oups, I had troubles fetching the news for you... Try again later!")
        end
      end

      def self.stringify(hash)
        if hash[:years] != 0
          "About #{hash[:years]} #{hash[:years] == 1 ? "year" : "years"} ago"
        elsif hash[:months] != 0
          "About #{hash[:months]} #{hash[:months] == 1 ? "month" : "months"} ago"
        elsif hash[:weeks] != 0
          hash[:weeks] += 1 if hash[:days] > 4
          "About #{hash[:weeks]} #{hash[:weeks] == 1 ? "week" : "weeks"} ago"
        elsif hash[:days] != 0
          hash[:days] += 1 if hash[:hours] > 12
          "About #{hash[:days]} #{hash[:hours] == 1 ? "day" : "days"} ago"
        elsif hash[:hours] != 0
          hash[:hours] += 1 if hash[:minutes] > 30
          "About #{hash[:hours]} #{hash[:hours] == 1 ? "hour" : "hours"} ago"
        elsif hash[:minutes] != 0
          hash[:minutes] += 1 if hash[:seconds] > 30
          "About #{hash[:minutes]} #{hash[:minutes] == 1 ? "minute" : "minutes"} ago"
        else
          "Just now"
        end
      end

      Commands::register("news", self) if Config.locale != nil and Config.limit_news != nil
    end
  end
end
