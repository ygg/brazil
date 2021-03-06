require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Activity do
  before(:each) do
    @valid_attributes = {
      :name => "value for name",
      :description => "value for description",
      :schema => "value for schema",
      :state => "value for state",
      :app_id => "1"
    }
    @activity = Activity.new(@valid_attributes)
  end

  it "should an activity instance given valid attributes" do
    @activity.should be_valid
  end

  it "should update the state to versioned" do
    @activity.should_receive(:update_attribute).with(:state, Activity::STATE_VERSIONED)
    @activity.versioned!
  end

  describe "when calling versioned?" do
    it "should be versioned" do
      @activity.stub!(:state).and_return(Activity::STATE_VERSIONED)
      @activity.versioned?.should be_true
    end

    it "should not be versioned" do
      @activity.stub!(:state).and_return(Activity::STATE_DEVELOPMENT)
      @activity.versioned?.should be_false
    end
  end
end
