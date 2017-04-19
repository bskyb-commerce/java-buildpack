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
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/framework'

module JavaBuildpack
  module Framework

    # Encapsulates the functionality for enabling zero-touch AppDynamics support.
    class AppDynamicsAgent < JavaBuildpack::Component::VersionedDependencyComponent

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
        set_logs_dir java_opts
        
        java_opts.add_system_property('appdynamics.http.proxyHost', '$WEB_PROXY_HOST') if !proxy_host.nil? && !proxy_host.empty?
        java_opts.add_system_property('appdynamics.http.proxyUser', '$WEB_PROXY_USER') if !proxy_user.nil? && !proxy_user.empty?
        java_opts.add_system_property('appdynamics.http.proxyPassword', '$WEB_PROXY_PASS') if !proxy_password.nil? && !proxy_password.empty?
        java_opts.add_system_property('appdynamics.http.proxyPort', '$WEB_PROXY_PORT') if !proxy_port.nil?

      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        @application.services.one_service? FILTER, 'host-name'
      end

      private

      FILTER = /app[-]?dynamics/
      PROXY_FILTER = /proxy/
      
      private_constant :FILTER
      private_constant :PROXY_FILTER

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

      def set_logs_dir(java_opts)
        java_opts.add_system_property('appdynamics.agent.logs.dir ', @droplet.sandbox + 'logs')
      end

      def proxy_host
        @application.services.find_service(PROXY_FILTER)['credentials']['host']
      end

      def proxy_user
        @application.services.find_service(PROXY_FILTER)['credentials']['username']
      end

      def proxy_password
        @application.services.find_service(PROXY_FILTER)['credentials']['password']
      end

      def proxy_port
        @application.services.find_service(PROXY_FILTER)['credentials']['port']
      end

    end

  end
end
