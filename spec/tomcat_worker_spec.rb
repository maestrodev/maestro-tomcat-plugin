# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'spec_helper'

describe MaestroDev::Plugin::TomcatWorker do

  before(:all) do
    Maestro::MaestroWorker.mock!
  end

  describe "deploy()" do

    before :all do
      `touch /tmp/webapp.war`
    end

    @@user = 'user'
    @@password = 'password'
    @@host = '127.0.0.1'
    @@port = 19090
    @@web_path = '/centrepoint'
    @@path = '/tmp/webapp.war'

    @@success = "Successfully put file #{@@path} To Remote Server OK - Deployed application at context path #{@@web_path}"
    @@rejected = "Timeout"
    @@unknown = "name or service not known"
    @@missing_path = "path not specified"

    it "should detect missing input fields (host + port specified)" do
      workitem = {'fields' => {
                                 'host' => 'adiosnugget',
                                 'port' => "22",
                                 'user' => "tomcat",
                                 'password' => "tomcat",
                                 'web_path' => "/centrepoint"
                                 }}

       subject.perform(:deploy, workitem)

       workitem['fields']['__error__'].should include(@@missing_path)
    end

    it "should detect missing input fields (host + port not specified)" do
      workitem = {'fields' => {
                                 'tomcat_root_url' => 'http://adiosnugget:22',
                                 'user' => "tomcat",
                                 'password' => "tomcat",
                                 'web_path' => "/centrepoint"
                                 }}

      subject.perform(:deploy, workitem)
      workitem['fields']['__error__'].should include(@@missing_path)
      workitem['fields']['__error__'].should_not include('user not specified')
      workitem['fields']['__error__'].should_not include('password not specified')
    end

    it "should detect missing input fields (user + pass specified insecurely)" do
      workitem = {'fields' => {
                                 'tomcat_root_url' => 'http://tomcat:tomcat@adiosnugget:22',
                                 'web_path' => "/centrepoint"
                                 }}

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should include(@@missing_path)
      workitem['fields']['__error__'].should_not include('user not specified')
      workitem['fields']['__error__'].should_not include('password not specified')
    end

    it "should deploy a war (host, port, default root ==> i.e. Legacy)" do
       workitem = {'fields' => {
                                  'path' => @@path,
                                  'host' => @@host,
                                  'port' => @@port,
                                  'user' => @@user,
                                  'password' => @@password,
                                  'web_path' => @@web_path
                                  }}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_return(:body => 'OK - Server info')
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/list").to_return(:body => 'OK Did It')
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should be_nil
      workitem['__output__'].should include(@@success)
    end

    it "should deploy a war (tomcat_root_url) (default root [/])" do
       workitem = {'fields' => {
                                  'path' => @@path,
                                  'tomcat_root_url' => "http://#{@@host}:#{@@port}/",
                                  'user' => @@user,
                                  'password' => @@password,
                                  'web_path' => @@web_path
                                  }}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_return(:body => 'OK - Server info')
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/list").to_return(:body => 'OK Did It')
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should be_nil
      workitem['__output__'].should include(@@success)
    end

    it "should deploy a war (tomcat_root_url) (specified root [tomcat])" do
       workitem = {'fields' => {
                                  'path' => @@path,
                                  'tomcat_root_url' => "http://#{@@host}:#{@@port}/tomcat",
                                  'user' => @@user,
                                  'password' => @@password,
                                  'web_path' => @@web_path
                                  }}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/tomcat/manager/text/serverinfo").to_return(:body => 'OK - Server info')
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/tomcat/manager/text/list").to_return(:body => 'OK Did It')
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/tomcat/manager/text/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should be_nil
      workitem['__output__'].should include(@@success)
    end

    it "should deploy a war Tomcat 6 fallback" do
       workitem = {'fields' => {
                                  'path' => @@path,
                                  'host' => @@host,
                                  'port' => @@port,
                                  'user' => @@user,
                                  'password' => @@password,
                                  'web_path' => @@web_path
                                  }}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_return(:code => 404)
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/serverinfo").to_return(:body => 'OK - Server info')
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/list").to_return(:body => 'OK Did It')
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should be_nil
      workitem['__output__'].should include(@@success)
    end


    it "should redeploy the same war" do
      workitem = {'fields' => {
                                  'path' => @@path,
                                  'host' => @@host,
                                  'port' => @@port,
                                  'user' => @@user,
                                  'password' => @@password,
                                  'web_path' => @@web_path
                                 }}

      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_return(:body => "OK - Server info")
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/list").to_return(:body => "OK Did It... ps found your war #{@@web_path}")
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/undeploy?path=#{@@web_path}").to_return(:body => "OK Deleted that pesky webapp #{@@web_path} for you")

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should be_nil
      workitem['__output__'].should include(@@success)
      workitem['__output__'].should include("Deleted that pesky webapp #{@@web_path} for you")
    end

    it 'should act rejected if tomcat not running at host' do
      workitem = {'fields' => {
                                'path' => @@path,
                                'host' => @@host,
                                'port' => @@port,
                                'user' => @@user,
                                'password' => @@password,
                                'web_path' => @@web_path,
                                'timeout' => 1
                               }}

      # Tomcat 7 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_timeout
      # Tomcat 6 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/serverinfo").to_timeout

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should include(@@rejected)
    end

    it 'should act rejected if tomcat not running at host (tomcat_root_url)' do
      workitem = {'fields' => {
                                'path' => @@path,
                                'tomcat_root_url' => "http://#{@@host}:#{@@port}",
                                'user' => @@user,
                                'password' => @@password,
                                'web_path' => @@web_path,
                                'timeout' => 1
                               }}

      # Tomcat 7 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_timeout
      # Tomcat 6 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/serverinfo").to_timeout

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should include(@@rejected)
    end

    it 'should report if host not found' do
      workitem = {'fields' => {
                                'path' => @@path,
                                'host' => @@host,
                                'port' => @@port,
                                'user' => @@user,
                                'password' => @@password,
                                'web_path' => @@web_path,
                                'timeout' => 1
                                }}

      # Tomcat 7 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_raise(SocketError.new("initialize: name or service not known"))
      # Tomcat 6 attempt
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/serverinfo").to_raise(SocketError.new("initialize: name or service not known"))

      subject.perform(:deploy, workitem)

      workitem['fields']['__error__'].should include(@@unknown)
    end

    it "should add leading front slash if missing from web_path" do
      workitem = {'fields' => {
                                'path' => @@path,
                                'host' => @@host,
                                'port' => @@port,
                                'user' => @@user,
                                'password' => @@password,
                                'web_path' => "centrepoint"
                               }}
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/serverinfo").to_return(:body => 'OK - Server info')
      stub_request(:get, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/list").to_return(:body => 'OK Did It')
      stub_request(:put, "http://#{@@user}:#{@@password}@#{@@host}:#{@@port}/manager/text/deploy?path=#{@@web_path}&war=file:#{@@path}").to_return(:body => "OK - Deployed application at context path #{@@web_path}")

      subject.perform(:deploy, workitem)

      workitem['fields']['web_path'].should eql('/centrepoint')
    end
  end

end
