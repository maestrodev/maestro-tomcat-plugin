# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'rest-client'

module MaestroDev
  module Plugin

    class TomcatWorker < Maestro::MaestroWorker

      def deploy
        validate_deploy_parameters

        write_output("\nStarting Deploy File To Tomcat")

        try = 1

        while try <= @max_connect_attempts
          write_output "\nAttempting connection to Tomcat server (attempt ##{try} of #{@max_connect_attempts})"

          begin
            delete_war if list_wars.match(/#{@web_path}/)

            try = @max_connect_attempts + 1
            write_output  "\nSuccessfully Connected To Tomcat Server\n"
          rescue PluginError => pie
            if pie.message.include?("Connection refused") && try <= @max_connect_attempts
              try += 1
              sleep @timeout
            else
              # Too many attempts? Let error through
              raise pie
            end
          end
        end

        put_war
      end

      def undeploy
        validate_undeploy_parameters

        delete_war
      end

      def list
        validate_list_inputs

        list_wars
      end

      private

      def validate_common_parameters
        # We use restclient, and this method is called before any task is
        # executed, so set up proxy here.... once
        RestClient.proxy = ENV['http_proxy'] if ENV.has_key?('http_proxy')

        errors = []

        @host = get_field('host', '')
        @port = get_int_field('port', 80)
        @user = get_field('user', '')
        @password = get_field('password', '')
        @timeout = get_int_field('timeout', 90)
        @max_connect_attempts = get_int_field('max_connect_attempts', 5)

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
        errors << "file not found '#{@path}" if !File.exists? @path

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

      def get_response(url, command, operation_text)
        getter = RestClient::Resource.new(
          "#{url}/#{command}",
           :user => @user,
           :password => @password,
           :timeout => 60,
           :open_timeout => 60)
        return check_ok_response(operation_text) { getter.get(:content_type => 'application/text') }
      end

      def check_ok_response(operation_text)
        begin
          response = yield
        rescue RestClient::ResourceNotFound => e
          raise PluginError, "HTTP Error talking to Tomcat while performing operation '#{operation_text}': #{e.class} #{e}"
        end

        # If this is a 'ok' type response, look for OK.
        # I think this is actually not needed 
        raise PluginError, "Non-OK response from Tomcat while performing operation '#{operation_text}': #{response}" unless response.match(/OK/)

        return response
      end

      def manager_url
        # We could let this be configured, but for now let's try to detect
        # TODO: also support SSL and a context base
        @manager_url ||= detect_manager_url
      end

      def detect_manager_url
        alternatives = [
          "http://#{@host}:#{@port}/manager/text",  # Tomcat 7
          "http://#{@host}:#{@port}/manager"        # Tomcat 6
        ]

        url = alternatives.find { |test_url|
          begin
            response = get_response(test_url, "serverinfo", "locate tomcat serverinfo page")
            true
          rescue PluginError
            Maestro.log.info "Tomcat not found at #{test_url}"
            false
          end
        }

        raise PluginError, "Could not locate tomcat manager at any of: #{alternatives.join(', ')}" unless url

        return url
      rescue StandardError => e
        raise PluginError, "Unable to connect to Tomcat: #{e}"
      end

      def list_wars
        response = get_response(manager_url, "list", "list wars") || ''

        write_output("\nApp list:\n#{response}", :buffer => true)

        response
      end

      def delete_war
        response = get_response(manager_url, "undeploy?path=#{@web_path}", "delete war #{@web_path}")

        write_output("\nSuccessfully deleted app at #{@web_path} from remote server (#{response})", :buffer => true)
        save_output_value('war', @web_path)
      end

      def put_war
        begin
          putter = RestClient::Resource.new(
            "#{manager_url}/deploy?path=#{@web_path}&war=file:#{@path}",
            :user => @user,
            :password => @password,
            :timeout => 3600,
            :open_timeout => 60)

          response = nil

          # RestClient does support streams, you they just seem intent on making it look like they're using strings
          # (to the point of aliasing "to_s" to "read"
          File.open(@path, "rb") do |file|
            response = check_ok_response("upload war #{@web_path}") { putter.put(file, :content_type => 'application/binary') }
          end

          write_output("\nSuccessfully put file #{@path} To Remote Server #{response}", :buffer => true)
          save_output_value('war', @web_path)
        rescue Exception => e
          raise PluginError, "Failed To Put File #{@path} To Remote Server #{e}"
        end
      end
    end
  end
end
