#encoding: utf-8

module Visjar
  class Visjar
    def initialize
      @answers  = YAML.load_file(File.join(File.dirname(__FILE__), '../config/answers.yml'))['repeats']
      @client  = Slack::RealTime::Client.new
    end

    def init!
      # On connexion, log
      @client.on(:hello) do |_|
        Log.info("#{self.class} | Connected as '#{Config.names.first}' to #{Config.url}")
        Log.info("#{self.class} | Using #{Commands.commands.keys.join(', ')}.")
      end

      @client.on([:channel_joined, :group_joined]) do |slack|
        Log.info("#{self.class} | Joined '#{slack['channel']['name']}'")
        Commands::Help.run(@client, {'channel' => slack['channel']['id']}, nil)
      end

      # On message, check if its for us, then invoke the appropriate command
      @client.on(:message) do |slack|
        # "@visjar do something" (ping)
        explicit = (slack['text'] and (slack['text'].match(/^<@#{Config.id}>:?\s?/) != nil))
        # "do something" (MP)
        implicit = (Config.ims.any?{ |im| im['id'] == slack['channel'] })

        if slack['user'] and slack['user'] != Config.id and (explicit or implicit)
          # Clean the sentence in order to be processed by Recast.AI
          slack['text'].gsub!(/^<@#{Config.id}>:?\s?/, "")

          recast = JSON.parse(HTTParty.post("https://api.recast.ai/request",
                                 :body    => {'text' => slack['text']},
                                 :headers => {'Authorization' => "Token #{Config.recast_key}"}).body)
          #ap recast # TODO

          if recast.empty?
            @client.send_message(slack['channel'], "Oups <@#{slack['user']}>, looks like Recast.AI can't help me this time...")
          elsif recast['error'] != nil
            @client.send_message(slack['channel'], "Sorry <@#{slack['user']}> but there's an error: '#{recast['error']}'")
          else
            Log.info("#{self.class} | Received '#{recast['source']}' tagged as '#{recast['intents'].any? ? recast['intents'].first : 'nothing'}', as '#{explicit ? 'explicit' : 'implicit'}'.")

            if recast['intents'].any?
              Commands.invoke(@client, slack, recast)
            elsif ['what', 'where', 'who', 'when', 'how', 'why'].include?(recast['sentences'].first["type"])
              Commands::Search.run(@client, slack, recast)
            else
              @client.send_message(slack['channel'], @answers.sample)
            end
          end
        end
      end

      # On error, log
      @client.on(:error) do |slack|
        Log.error("#{self.class} | #{slack}")
      end
    end

    def run!
      # Get the auth infos for the user
      auth = @client.web_client.auth_test

      # Set the config from the response
      Config.url     = auth['url']
      Config.id      = auth['user_id']
      Config.team    = auth['team']
      Config.team_id = auth['team_id']
      Config.names   = ["#{auth['user']}", "#{auth['user']}:", "<@#{auth['user_id']}>", "<@#{auth['user_id']}>:"]
      Config.ims     = @client.web_client.im_list['ims']

      # Start the client
      @client.start!
    end
  end
end
