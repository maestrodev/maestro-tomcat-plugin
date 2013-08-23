# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'rest-client'

module MaestroDev
  module Plugin

    class TomcatWorker < Maestro::MaestroWorker

      def deploy
        validate_deploy_parameters

#        Maestro.log.info "Inputs:\n  path =       #{@path}\n  url =        #{@url}\n  options =     #{@options}"

        write_output("\nStarting Deploy File To Tomcat")

        max_tries = 5
        try = 1


        while try <= max_tries
          Maestro.log.debug "Attempting Connection To Tomcat Server Try #{try}"
          write_output "\nAttempting Connection To Tomcat Server Try #{try}"

          begin
            delete_war(@web_path) if list_wars.match(/#{@web_path}/)

            try = max_tries + 1
            Maestro.log.debug "Successfully Connected To Tomcat Server"
            write_output  "Successfully Connected To Tomcat Server\n"
          rescue PluginError => pie
            if pie.message.include?("Connection refused") && try <= max_tries
              try += 1
              sleep @timeout
            else
              # Too many attempts? Let error through
              raise pie
            end
          end
        end

        war = read_war
        put_war(read_war)
      end

      def undeploy
        validate_undeploy_parameters

        Maestro.log.info "Inputs:\n  path =       #{@path}\n  url =        #{@url}\n  options =     #{@options}"

        delete_war(@web_path)
      end

      def list
        validate_list_inputs

        list_wars()
      end

      private

      def validate_common_parameters
        # We use restclient, and this method is called before any task is
        # executed, so set up proxy here.... once
        RestClient.proxy = ENV['http_proxy'] if ENV.has_key?('http_proxy')

        errors = []

        @host = get_field('host', '')
        @port = intify(get_field('port'), 80)
        @user = get_field('user', '')
        @password = get_field('password', '')
        @timeout = intify(get_field('timeout'), 90)

        errors << 'host not specified' if @host.empty?
        errors << 'port not specified' if @port < 1
        errors << 'user not specified' if @user.empty?
        errors << 'password not specified' if @password.empty?

        errors
      end

      def validate_deploy_parameters
        errors = validate_common_parameters

        @path = get_field('path', '')
        @web_path = get_field('web_path', '')

        errors << 'path not specified' if @path.empty?
        errors << 'web_path not specified' if @web_path.empty?

        if @web_path.match(/^\//).nil?
          @web_path = "/#{@web_path}"
          set_field('web_path', @web_path)
        end

        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end

      def validate_undeploy_parameters
        errors = validate_common_parameters

        @web_path = get_field('web_path', '')

        errors << 'web_path not specified' if @web_path.empty?

        if @web_path.match(/^\//).nil?
          @web_path = "/#{@web_path}"
          set_field('web_path', @web_path)
        end

        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end

      def validate_list_parameters
        errors = validate_common_parameters

        if !errors.empty?
          raise ConfigError, "Configuration errors: #{errors.join(', ')}"
        end
      end

      def intify(value, default = 0)
        res = default

        if value
          if value.is_a?(Fixnum)
            res = value
          elsif value.respond_to?(:to_i)
            res = value.to_i
          end
        end

        res
      end

      def get_response(url, command)
        getter = RestClient::Resource.new(
          "#{url}/#{command}",
           :user => @user,
           :password => @password,
           :timeout => 60,
           :open_timeout => 60)
        response = getter.get :content_type => 'application/text'
      end

      def manager_url
        # We could let this be configured, but for now let's try to detect
        # TODO: also support SSL and a context base
        @manager_url ||= detect_manager_url
      end

      def detect_manager_url
        # Tomcat 7
        url = "http://#{@host}:#{@port}/manager/text"
        begin
          response = get_response(url, "serverinfo")
          if response.match(/OK/)
            write_output("Connected to Tomcat server:\n#{response}")
            return url
          else
            Maestro.log.info "Tomcat not found at #{url} (will try alternatives), response:\n#{response}"
          end
        rescue => e
          write_output("Unable to connect to Tomcat: #{e}")
        end

        # Tomcat 6
        url = "http://#{@host}:#{@port}/manager"
        begin
          response = get_response(url, "serverinfo")
          if response.match(/OK/)
            write_output("Connected to Tomcat server:\n#{response}")
          else
            raise PluginError, "Tomcat not found at #{url} (No more alternatives to try), response:\n#{response}"
          end
        rescue => e
          raise PluginError, "Unable to connect to Tomcat: #{e}"
        end

        url
      end

      def list_wars
        begin
          response = get_response(manager_url, "list")

          if response.match(/OK/)
            write_output("Successfully listed apps from remote server\n#{response}", :buffer => true)
          else
            raise PluginError, response
          end
        rescue Exception => e
          raise PluginError, "Failed to list apps from remote server #{e}"
        end

        response || ''
      end

      def delete_war(web_path)
        begin
          response = get_response(manager_url, "undeploy?path=#{web_path}")

          if response.match(/OK/)
            write_output("\nSuccessfully deleted app at #{web_path} from remote server (#{response})", :buffer => true)
            save_output_value('war', web_path)
          else
            raise PluginError, response
          end
        rescue Exception => e
          raise PluginError, "Failed to delete war #{web_path} from remote server #{e}"
        end
      end

      def read_war
        raise PluginError, "File not found '#{@path}" if !File.exists? @path

        open(@path, "rb") {|io| io.read }
      end

      def put_war(war)
        begin
          putter = RestClient::Resource.new(
            "#{manager_url}/deploy?path=#{@web_path}&war=file:#{@path}",
            :user => @user,
            :password => @password,
            :timeout => 3600,
            :open_timeout => 60)

          response = putter.put war, :content_type => 'application/binary'

          if response.match(/OK/)
            write_output("\nSuccessfully put file #{@path} To Remote Server #{response}", :buffer => true)
            save_output_value('war', @path)
          else
            raise PluginError, response
          end
        rescue Exception => e
          raise PluginError, "Failed To Put File #{@path} To Remote Server #{e}"
        end
      end
    end
  end
end
