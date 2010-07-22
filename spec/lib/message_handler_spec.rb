require File.dirname(__FILE__) + '/../spec_helper'

describe MessageHandler do
  before do
    @handler = MessageHandler.new
    @message_body = "I want to pump you up" 
    @message_urls = ["http://www.google.com/", "http://yahoo.com/", "http://foo.com/"]

  end

  describe 'GET messages' do
    describe 'creating a GET query' do 
      it 'should be able to add a GET query to the queue with required destinations' do
        EventMachine.run{
          @handler.add_get_request(@message_urls)
          @handler.size.should == @message_urls.size
          EventMachine.stop
        }
      end

    end

    describe 'processing a GET query' do
      it 'should remove sucessful http requests from the queue' do
        request = FakeHttpRequest.new(:success)
        request.should_receive(:get).and_return(request)
        EventMachine::HttpRequest.stub!(:new).and_return(request)
        
        EventMachine.run { 
          @handler.add_get_request("http://www.google.com/")
          @handler.size.should == 1
          @handler.process
          @handler.size.should == 0
          EventMachine.stop
        }
      end


      it 'should only retry a bad request three times ' do
        request = FakeHttpRequest.new(:failure)
        request.should_receive(:get).exactly(MessageHandler::NUM_TRIES).times.and_return(request)
        EventMachine::HttpRequest.stub!(:new).and_return(request)

        EventMachine.run {
          @handler.add_get_request("http://asdfsdajfsdfbasdj.com/")
          @handler.size.should == 1
          @handler.process
          @handler.size.should == 0

        EventMachine.stop
      }
      end
    end
  end

  describe 'POST messages' do
    

    it 'should be able to add a post message to the queue' do
      EventMachine.run {
        @handler.size.should ==0
        @handler.add_post_request(@message_urls.first, @message_body)
        @handler.size.should == 1
        
        EventMachine.stop
      }
    end

    it 'should be able to insert many posts into the queue' do
      EventMachine.run {
        @handler.size.should == 0
        @handler.add_post_request(@message_urls, @message_body)
        @handler.size.should == @message_urls.size
        EventMachine.stop
      }
    end

    it 'should post a single message to a given URL' do
      request = FakeHttpRequest.new(:success)
      request.should_receive(:post).and_return(request)
      EventMachine::HttpRequest.stub!(:new).and_return(request)
      EventMachine.run{
        
        @handler.add_post_request(@message_urls.first, @message_body)
        @handler.size.should == 1
        @handler.process
        @handler.size.should == 0 

        EventMachine.stop 
      
      }
    end
  end

  describe "Mixed Queries" do 
    
    it 'should process both POST and GET requests in the same queue' do
      request = FakeHttpRequest.new(:success)
      request.should_receive(:get).exactly(3).times.and_return(request)
      request.should_receive(:post).exactly(3).times.and_return(request)
      EventMachine::HttpRequest.stub!(:new).and_return(request)
 
      EventMachine.run{
        @handler.add_post_request(@message_urls,@message_body)
        @handler.size.should == 3
        @handler.add_get_request(@message_urls)
        @handler.size.should == 6
        @handler.process
        timer = EventMachine::Timer.new(1) do
          @handler.size.should == 0
          EventMachine.stop
        end
      }
    end

    it 'should be able to have seperate POST and GET have different callbacks' do
      request = FakeHttpRequest.new(:success)
      request.should_receive(:get).exactly(1).times.and_return(request)
      request.should_receive(:post).exactly(1).times.and_return(request)
      @handler.should_receive(:send_to_seed).once
      
      EventMachine::HttpRequest.stub!(:new).and_return(request)

      EventMachine.run{
        @handler.add_post_request(@message_urls.first,@message_body)
        @handler.add_get_request(@message_urls.first)
        @handler.process

        EventMachine.stop
      }

    end
  end

  describe 'ostatus_subscribe' do
    it 'should be able to add a GET query to the queue with required destinations' do
      request = FakeHttpRequest.new(:success)
      request.should_receive(:get).exactly(1).times.and_return(request)
      request.stub!(:callback).and_return(true)
      
      EventMachine::HttpRequest.stub!(:new).and_return(request)

      EventMachine.run{
        @handler.add_subscription_request("http://evan.status.net/")
        @handler.size.should == 1

        @handler.process
        EventMachine.stop
      }
    end

  end

  describe 'hub_publish' do
    it 'should correctly queue up a pubsubhub publish request' do
      destination = "http://identi.ca/hub/"
      feed_location = "http://google.com/"
      
      EventMachine.run {
        @handler.add_hub_notification(destination, feed_location)
        q = @handler.instance_variable_get(:@queue)

        message = ""
        q.pop{|m| message = m} 

        message.destination.should == destination
        message.body.should  == feed_location

        EventMachine.stop
      }
    end

    it 'should notify the hub about new content' do
      request = FakeHttpRequest.new(:success)
      request.should_receive(:publish).exactly(1).times.and_return(request)
      EventMachine::PubSubHubbub.stub!(:new).and_return(request)

      EventMachine.run {
        @handler.add_hub_notification("http://identi.ca/hub", "http://google.com/feed")
        @handler.size.should == 1
        @handler.process
        @handler.size.should == 0
        EventMachine.stop
      }
    end

  end

  describe 'hub_subscribe' do

    it 'should process an ostatus subscription' do
      request = FakeHttpRequest.new(:success)

      Diaspora::OStatusParser.stub!(:find_hub).and_return("http://hub.google.com")
      MessageHandler.stub!(:add_hub_subscription_request).and_return(true)

      Diaspora::OStatusParser.stub!(:parse_sender)
      Diaspora::OStatusParser.should_receive(:find_hub)
      @handler.should_receive(:add_hub_subscription_request)
      Diaspora::OStatusParser.should_receive(:parse_sender)

      g = mock("Message")
      g.stub!(:destination).and_return("google")

      @handler.process_ostatus_subscription(g, request)    
    end

    
  end

end

class FakeHttpRequest
  def initialize(callback_wanted)
    @callback = callback_wanted
  end
  def response 
    "NOTE YOU ARE IN FAKE HTTP"
  end

  def post; end
  def get; end
  def callback(&b)
    b.call if @callback == :success
  end
  def errback(&b)
    b.call if @callback == :failure
  end
end

