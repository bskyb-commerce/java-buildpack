# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013-2017 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'net/http'
require 'uri'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'
require 'java_buildpack/logging/logger_factory'

module JavaBuildpack
  module Framework

    # Encapsulates the functionality for enabling zero-touch AppDynamics support.
    class AppDynamicsAgent < JavaBuildpack::Component::VersionedDependencyComponent
      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        super(context)
        @logger = JavaBuildpack::Logging::LoggerFactory.instance.get_logger AppDynamicsAgent
      end
      
      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download_zip(false, @droplet.sandbox, 'AppDynamics Agent')
        @droplet.copy_resources
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
        credentials = @application.services.find_service(FILTER)['credentials']
        java_opts   = @droplet.java_opts
        java_opts.add_javaagent(@droplet.sandbox + 'javaagent.jar')

        application_name java_opts, credentials
        tier_name java_opts, credentials
        node_name java_opts, credentials
        account_access_key java_opts, credentials
        account_name java_opts, credentials
        host_name java_opts, credentials
        port java_opts, credentials
        ssl_enabled java_opts, credentials

        if !@application.services.find_service(PROXY_FILTER).nil?
          proxy_credentials = @application.services.find_service(PROXY_FILTER)['credentials']
          proxy_host java_opts, proxy_credentials
          proxy_port java_opts, proxy_credentials
          proxy_user java_opts, proxy_credentials
          proxy_password_file java_opts, proxy_credentials
        end
        
        @logger.debug("-----> Looking for API credentials.")
        # Do Event Notification if we have API Credentials.
        if !@application.services.find_service(API_FILTER).nil?
          deployment_notifier @application.services.find_service(API_FILTER)['credentials'], credentials
        end
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        @application.services.one_service? FILTER, 'host-name'
      end

      private

      API_FILTER = /appd-api/
      FILTER = /app[-]?dynamics/
      PROXY_FILTER = /proxy/

      private_constant :FILTER
      private_constant :PROXY_FILTER
      private_constant :API_FILTER
      
      # If api-user api-name are set on credenitals and appd-build set in env.
      # tell appd about this release.
      def deployment_notifier(api_credentials, credentials)
        @logger.debug("-----> Trying AppD Deployment Notification.")
        if api_credentials['username'] and api_credentials['password']
            @logger.debug("----> Making Request");
            host_name = credentials['host-name']
            port = credentials['port']
            appd_name = credentials['app-name']
            app_name = credentials['tier-name'] || @configuration['default_application_name'] || @application.details['application_name']
            protocol = 'https';
            api_user = api_credentials['username']
            account = credentials['account-name']
            
            events_uri = URI.parse("#{protocol}://#{host_name}:#{port}/controller/rest/applications/#{appd_name}/events")
            
            events_uri.query = URI.encode_www_form(
            'eventtype' => 'APPLICATION_DEPLOYMENT',
            'summary' => URI.encode("Deploying: #{app_name}"),
            'severity' => 'INFO'
            )
              
            request = Net::HTTP::Post.new(events_uri.path)
            request.basic_auth "#{api_user}@#{account}", api_credentials['password']

            if !@application.services.find_service(PROXY_FILTER).nil?
              @logger.debug("Using Proxy to call AppD API.")
              proxy_credentials = @application.services.find_service(PROXY_FILTER)['credentials']
              @logger.debug(proxy_credentials)
              @logger.debug("Requesting> #{events_uri}")
              proxy = Net::HTTP::Proxy(proxy_credentials['host'], proxy_credentials['port'], proxy_credentials['username'], proxy_credentials['password'])
              res = proxy.start(events_uri.host, events_uri.port, :use_ssl => events_uri.scheme == 'https') do |http|
                http.request(request)
              end
              @logger.debug(res.code)
              @logger.debug(res.body)
            else
              sock = Net::HTTP.new(events_uri.host, events_uri.port)
              sock.use_ssl = true
              res = sock.start { |http| http.request(request) }
            end
        end
      end
      
      def application_name(java_opts, credentials)
        name = credentials['application-name'] || @configuration['default_application_name'] ||
          @application.details['application_name']
        java_opts.add_system_property('appdynamics.agent.applicationName', name.to_s)
      end

      def account_access_key(java_opts, credentials)
        account_access_key = credentials['account-access-key']
        java_opts.add_system_property 'appdynamics.agent.accountAccessKey', account_access_key if account_access_key
      end

      def account_name(java_opts, credentials)
        account_name = credentials['account-name']
        java_opts.add_system_property 'appdynamics.agent.accountName', account_name if account_name
      end

      def host_name(java_opts, credentials)
        host_name = credentials['host-name']
        raise "'host-name' credential must be set" unless host_name
        java_opts.add_system_property 'appdynamics.controller.hostName', host_name
      end

      def node_name(java_opts, credentials)
        name = credentials['node-name'] || @configuration['default_node_name']
        java_opts.add_system_property('appdynamics.agent.nodeName', name.to_s)
      end

      def port(java_opts, credentials)
        port = credentials['port']
        java_opts.add_system_property 'appdynamics.controller.port', port if port
      end

      def ssl_enabled(java_opts, credentials)
        ssl_enabled = credentials['ssl-enabled']
        java_opts.add_system_property 'appdynamics.controller.ssl.enabled', ssl_enabled if ssl_enabled
      end

      def tier_name(java_opts, credentials)
        name = credentials['tier-name'] || @configuration['default_tier_name'] ||
          @application.details['application_name']
        java_opts.add_system_property('appdynamics.agent.tierName', name.to_s)
      end

      def proxy_host(java_opts, proxy_credentials)
        host = proxy_credentials['host']
        java_opts.add_system_property 'appdynamics.http.proxyHost', host if host
      end

      def proxy_user(java_opts, proxy_credentials)
        user = proxy_credentials['username']
        java_opts.add_system_property 'appdynamics.http.proxyUser', user if user
      end

      def proxy_port(java_opts, proxy_credentials)
        port = proxy_credentials['port']
        java_opts.add_system_property 'appdynamics.http.proxyPort', port if port
      end

      def proxy_password_file(java_opts, proxy_credentials)
        password = proxy_credentials['password']
        # needs to be a file.
        if password
          proxyFile = @droplet.sandbox + 'proxyPass.txt'
          FileUtils.mkdir_p proxyFile.parent

          File.write(proxyFile, password)

          java_opts.add_system_property 'appdynamics.http.proxyPasswordFile', proxyFile
        end
      end
    end
  end
end
