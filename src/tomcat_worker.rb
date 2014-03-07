# Copyright (c) 2013 MaestroDev.  All rights reserved.
require 'maestro_plugin'
require 'rest-client'

module MaestroDev
  module Plugin

    class TomcatWorker < Maestro::MaestroWorker

      URL_REGEX = '^(http(s)?):\/\/(?:(.*):(.*)@)?(?:([^:\/]*)(?::(\d+))?)(\/(?:.*))?'

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

        # This bit will support both a simple base url "/tomcat" or a fully specified url "http(s)://user:password@sample.com:port/tomcat"
        # The regex supports extracting (if present): scheme [1], 's' indicator [2], user [3], password [4], host [5], port [6], path [7]
        @tomcat_root_url = get_field('tomcat_root_url', '')

        path_bits = @tomcat_root_url.match(URL_REGEX)

        if path_bits
          # Prefer to use the user/password specified separately.  Use presence of specified user field to make determination
          # of which to use
          if @user.empty?
            @user = path_bits[3] || @user
            @password = path_bits[4] || @password
          end

          @host = path_bits[5]
          @port = as_int(path_bits[6], 0)
          @tomcat_root_url = "#{path_bits[1]}://#{@host}#{@port > 0 ? ":#{@port}" : ''}#{path_bits[7]}"
        else
          @tomcat_root_url = URI.join("http://#{@host}:#{@port}", @tomcat_root_url).to_s
          errors << 'port not specified (either in port or tomcat_root_url)' if @port < 1
        end

        # Must end with a '/' or the URI.join method will cause problems (it may remove the path component)
        @tomcat_root_url = @tomcat_root_url + '/' unless @tomcat_root_url.end_with?('/')

        @timeout = get_int_field('timeout', 90)
        @max_connect_attempts = get_int_field('max_connect_attempts', 5)

        errors << 'host not specified (either in host or tomcat_root_url)' if @host.empty?
        errors << 'user not specified (either in user or tomcat_root_url)' if @user.empty?
        errors << 'password not specified (either in password or tomcat_root_url)' if @password.empty?

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

        post_validate(errors)
      end

      def validate_undeploy_parameters
        errors = validate_common_parameters

        @web_path = get_field('web_path', '')

        errors << 'web_path not specified' if @web_path.empty?

        if @web_path.match(/^\//).nil?
          @web_path = "/#{@web_path}"
          set_field('web_path', @web_path)
        end

        post_valiate(errors)
      end

      def validate_list_parameters
        post_validate(validate_common_parameters)
      end

      def post_validate(errors)

        # Only attempt to detect manager if we have no errors so far
        if errors.empty?
          begin
            @manager_url = detect_manager_url
          rescue ConfigError => e
            errors << e.message
          end
        end

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
        rescue RestClient::RequestTimeout => e
          raise PluginError, "Timeout while performing '#{operation_text}'"
        rescue SocketError => e
          raise PluginError, "SocketError while performing '#{operation_text}': #{e}"
        end

        # If this is a 'ok' type response, look for OK.
        # I think this is actually not needed 
        raise PluginError, "Non-OK response from Tomcat while performing operation '#{operation_text}': #{response}" unless response.match(/OK/)

        return response
      end

      def detect_manager_url
        alternatives = [
          URI.join(@tomcat_root_url, "manager/text").to_s,  # Tomcat 7
          URI.join(@tomcat_root_url, "manager").to_s        # Tomcat 6
        ]

        errors = []

        url = alternatives.find { |test_url|
          begin
            response = get_response(test_url, "serverinfo", "locate tomcat serverinfo page")
            true
          rescue PluginError => e
            # Logging has been err... removed from base plugin - best not to try
            # The config error below includes this info anyway
#            Maestro.log.info "Tomcat not found at #{test_url}"
            errors << "Alternative '#{test_url}': #{e.message}"
            false
          rescue StandardError => e
            errors << "Alternative #{test_url} returned unexpected error #{e.message}"
            false
          end
        }

        raise ConfigError, "Could not locate tomcat manager.  #{errors.join(', ')}" unless url

        return url
      rescue StandardError => e
        raise ConfigError, "Unable to connect to Tomcat: #{e}"
      end

      def list_wars
        response = get_response(@manager_url, "list", "list wars") || ''

        write_output("\nApp list:\n#{response}", :buffer => true)

        response
      end

      def delete_war
        response = get_response(@manager_url, "undeploy?path=#{@web_path}", "delete war #{@web_path}")

        write_output("\nSuccessfully deleted app at #{@web_path} from remote server (#{response})", :buffer => true)
        save_output_value('war', @web_path)
      end

      def put_war
        begin
          putter = RestClient::Resource.new(
            "#{@manager_url}/deploy?path=#{@web_path}&war=file:#{@path}",
            :user => @user,
            :password => @password,
            :timeout => 3600,
            :open_timeout => 60)

          response = nil

          # RestClient does support streams, you they just seem intent on making it look like they're using strings
          # (to the point of aliasing "to_s" to "read")
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
