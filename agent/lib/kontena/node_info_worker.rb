require 'docker'
require 'net/http'
require_relative 'logging'
require_relative 'helpers/node_helper'
require_relative 'helpers/iface_helper'

module Kontena
  class NodeInfoWorker
    include Kontena::Logging
    include Helpers::NodeHelper
    include Helpers::IfaceHelper

    attr_reader :queue

    ##
    # @param [Queue] queue
    def initialize(queue)
      @queue = queue
      Pubsub.subscribe('websocket:connected') do |event|
        self.publish_node_info
      end
      info 'initialized'
    end

    def start!
      Thread.new {
        loop do
          sleep 300
          self.publish_node_info
        end
      }
    end

    ##
    # Publish node info to queue
    #
    def publish_node_info
      info 'publishing node information'
      docker_info = Docker.info
      docker_info['PublicIp'] = self.public_ip
      docker_info['PrivateIp'] = self.private_ip
      event = {
          event: 'node:info',
          data: docker_info
      }
      self.queue << event
    rescue => exc
      error "publish_node_info: #{exc.message}"
    end

    ##
    # @return [String, NilClass]
    def public_ip
      if ENV['COREOS_PUBLIC_IPV4']
        ENV['COREOS_PUBLIC_IPV4']
      else
        Net::HTTP.get('whatismyip.akamai.com', '/')
      end
    rescue => exc
      error "Cannot resolve public ip: #{exc.message}"
      nil
    end

    # @return [String]
    def private_ip
      ip = interface_ip(private_interface)
      unless ip
        ip = interface_ip('eth0')
      end
      ip
    end

    # @return [String]
    def private_interface
      ENV['KONTENA_PEER_INTERFACE'] || 'eth1'
    end
  end
end
